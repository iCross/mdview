import AppKit
import Foundation
import Markdown
import Highlightr

/// AST-based Markdown → NSAttributedString renderer (swift-markdown).
///
/// Current strategy: use AST for syntax we can handle reliably; if we detect GFM table/task/image, fall back for the whole document.
/// This lets us introduce the AST pipeline incrementally without breaking existing behavior.
struct ASTMarkdownRenderer {
    let theme: NativeMarkdownTheme

    static func canRender(markdown: String) -> Bool {
        // swift-markdown focuses on CommonMark; the existing native parser in this repo already supports:
        // - pipe tables
        // - task lists
        // - images (NSTextAttachment)
        // Use a conservative policy: if we detect these, let the native parser handle everything.
        let s = markdown
        if s.contains("|") {
            // Heuristic: if we see a typical table separator line, treat it as a table.
            if s.range(of: #"(?m)^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$"#, options: .regularExpression) != nil {
                return false
            }
        }
        if s.range(of: #"(?m)^\s*[-*+]\s+\[[ xX]\]\s+"#, options: .regularExpression) != nil {
            return false
        }
        if s.contains("![") {
            return false
        }
        return true
    }

    func render(markdown: String) -> NSAttributedString {
        var v = Visitor(theme: theme)
        return v.convert(markdown: markdown)
    }

    private struct Visitor: MarkupVisitor {
        private let theme: NativeMarkdownTheme
        private var out = NSMutableAttributedString()
        private var currentAttributes: [NSAttributedString.Key: Any]
        private var blockQuoteDepth: Int = 0

        private enum ListContext {
            case unordered(depth: Int)
            case ordered(depth: Int, start: Int)
        }
        private var listStack: [ListContext] = []
        private static let highlightr: Highlightr? = Highlightr()

        init(theme: NativeMarkdownTheme) {
            self.theme = theme
            self.currentAttributes = [
                .font: theme.paragraphFont,
                .foregroundColor: theme.textColor,
                .paragraphStyle: theme.baseParagraphStyle
            ]
        }

        mutating func convert(markdown: String) -> NSAttributedString {
            let doc = Document(parsing: markdown)
            visit(doc)

            // Ensure the output ends with a newline (match the native parser behavior; helps NSTextView layout).
            if out.length > 0, !out.string.hasSuffix("\n") {
                out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
            }
            return out
        }

        mutating func defaultVisit(_ markup: any Markup) {
            visitChildren(of: markup)
        }

        private mutating func visitChildren(of markup: Markup) {
            for child in markup.children {
                visit(child)
            }
        }

        // MARK: - Inline

        mutating func visitText(_ text: Text) {
            out.append(NSAttributedString(string: text.string, attributes: currentAttributes))
        }

        mutating func visitSoftBreak(_ softBreak: SoftBreak) {
            // In a blockquote, using "\n" for soft breaks can be treated as a paragraph break and trigger paragraphSpacing.
            // In quote context, use U+2028 (line separator) to keep it as an in-paragraph line break.
            if blockQuoteDepth > 0 {
                out.append(NSAttributedString(string: "\u{2028}", attributes: currentAttributes))
            } else {
                out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
            }
        }

        mutating func visitLineBreak(_ lineBreak: LineBreak) {
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
        }

        mutating func visitEmphasis(_ emphasis: Emphasis) {
            let prev = currentAttributes
            currentAttributes[.font] = theme.italicFont
            visitChildren(of: emphasis)
            currentAttributes = prev
        }

        mutating func visitStrong(_ strong: Strong) {
            let prev = currentAttributes
            currentAttributes[.font] = theme.boldFont
            visitChildren(of: strong)
            currentAttributes = prev
        }

        mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
            let prev = currentAttributes
            currentAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            visitChildren(of: strikethrough)
            currentAttributes = prev
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            let baseFont = (currentAttributes[.font] as? NSFont) ?? theme.paragraphFont
            let attrs: [NSAttributedString.Key: Any] = [
                .font: theme.monoFont(ofSize: baseFont.pointSize),
                .foregroundColor: theme.textColor,
                .backgroundColor: theme.codeBackgroundColor,
                .paragraphStyle: theme.baseParagraphStyle
            ]
            out.append(NSAttributedString(string: inlineCode.code, attributes: attrs))
        }

        mutating func visitLink(_ link: Link) {
            let prev = currentAttributes
            var attrs = currentAttributes
            attrs[.foregroundColor] = theme.linkColor
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            if let dest = link.destination {
                attrs[.link] = dest
            }
            currentAttributes = attrs
            visitChildren(of: link)
            currentAttributes = prev
        }

        // MARK: - Blocks

        mutating func visitParagraph(_ paragraph: Paragraph) {
            let prev = currentAttributes
            currentAttributes[.paragraphStyle] = theme.baseParagraphStyle
            visitChildren(of: paragraph)
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
            currentAttributes = prev
        }

        mutating func visitHeading(_ heading: Heading) {
            let prev = currentAttributes
            currentAttributes[.font] = theme.headingFont(level: heading.level)
            currentAttributes[.paragraphStyle] = theme.headingParagraphStyle(level: heading.level)
            visitChildren(of: heading)
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
            currentAttributes = prev
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            // Use NSTextBlock for blockquote styling (same concept as the existing native parser).
            let block = NSTextBlock()
            block.backgroundColor = NSColor.clear
            block.setContentWidth(100, type: .percentageValueType)
            block.setWidth(10, type: .absoluteValueType, for: .padding)
            block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
            block.setBorderColor(theme.codeBorderColor, for: .minX)

            let p = NSMutableParagraphStyle()
            p.textBlocks = [block]
            p.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
            p.lineSpacing = theme.baseParagraphStyle.lineSpacing
            p.paragraphSpacing = 10

            let prev = currentAttributes
            currentAttributes[.paragraphStyle] = p
            currentAttributes[.foregroundColor] = theme.secondaryTextColor
            blockQuoteDepth += 1
            visitChildren(of: blockQuote)
            blockQuoteDepth -= 1
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
            currentAttributes = prev
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            // Reader: apply block styling + monospaced font; syntax highlighting is handled by Highlightr.
            let block = NSTextBlock()
            block.backgroundColor = theme.codeBackgroundColor
            block.setContentWidth(100, type: .percentageValueType)
            block.setWidth(10, type: .absoluteValueType, for: .padding)
            block.setWidth(1, type: .absoluteValueType, for: .border)
            block.setBorderColor(theme.codeBorderColor)

            let p = NSMutableParagraphStyle()
            p.textBlocks = [block]
            p.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
            p.lineSpacing = theme.baseParagraphStyle.lineSpacing
            p.paragraphSpacing = 10

            let baseAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.monoFont,
                .foregroundColor: theme.textColor,
                .paragraphStyle: p
            ]

            // Render the code block (keep the original text).
            if let hl = Self.highlightr {
                hl.theme.setCodeFont(theme.monoFont)
                _ = hl.setTheme(to: (NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) ? "paraiso-dark" : "paraiso-light")
                let highlighted = hl.highlight(codeBlock.code, as: nil, fastRender: true)
                if let highlighted {
                    let m = NSMutableAttributedString(attributedString: highlighted)
                    m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
                    out.append(m)
                    out.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                } else {
                    out.append(NSAttributedString(string: codeBlock.code + "\n", attributes: baseAttrs))
                }
            } else {
                out.append(NSAttributedString(string: codeBlock.code + "\n", attributes: baseAttrs))
            }

            // Mermaid: insert the diagram below the code block (mermaid.ink; non-blocking load).
            if let lang = codeBlock.language?.lowercased(), lang == "mermaid" {
                if let diagram = MermaidRenderer.makeAttachment(code: codeBlock.code, theme: theme, maxWidth: nil) {
                    let dp = NSMutableParagraphStyle()
                    dp.alignment = .center
                    dp.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
                    dp.lineSpacing = theme.baseParagraphStyle.lineSpacing
                    dp.paragraphSpacing = 10
                    dp.paragraphSpacingBefore = 4
                    dp.lineBreakMode = .byWordWrapping

                    let diagramOut = NSMutableAttributedString(attributedString: diagram)
                    diagramOut.addAttribute(.paragraphStyle, value: dp, range: NSRange(location: 0, length: diagramOut.length))
                    out.append(diagramOut)
                }
            }

            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
        }

        mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
            let depth = listStack.count
            listStack.append(.unordered(depth: depth))
            visitChildren(of: unorderedList)
            listStack.removeLast()
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
        }

        mutating func visitOrderedList(_ orderedList: OrderedList) {
            let depth = listStack.count
            listStack.append(.ordered(depth: depth, start: Int(orderedList.startIndex)))
            visitChildren(of: orderedList)
            listStack.removeLast()
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
        }

        mutating func visitListItem(_ listItem: ListItem) {
            let prev = currentAttributes

            let (prefix, depth): (String, Int)
            if let ctx = listStack.last {
                switch ctx {
                case .unordered(let d):
                    let bullets = ["•", "◦", "▪", "▫"]
                    let bullet = bullets[d % bullets.count]
                    prefix = "\(bullet)"
                    depth = d
                case .ordered(let d, let start):
                    let idx = start + listItem.indexInParent
                    prefix = "\(idx)."
                    depth = d
                }
            } else {
                prefix = "•"
                depth = 0
            }

            let p = NSMutableParagraphStyle()
            
            // Notes.app style: prefix indent + aligned text (tab stop + hanging indent).
            let depthIndent = CGFloat(depth) * 16
            let bulletIndent: CGFloat = 14 + depthIndent
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: theme.paragraphFont]).width
            let minTextIndent: CGFloat = 32 + depthIndent
            let textIndent = max(minTextIndent, bulletIndent + prefixWidth + 12)
            
            p.firstLineHeadIndent = bulletIndent
            p.headIndent = textIndent
            p.tabStops = [
                NSTextTab(textAlignment: .left, location: textIndent, options: [:])
            ]
            p.defaultTabInterval = textIndent
            p.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
            p.lineSpacing = theme.baseParagraphStyle.lineSpacing
            p.paragraphSpacing = 2

            currentAttributes[.paragraphStyle] = p
            currentAttributes[.font] = theme.paragraphFont
            currentAttributes[.foregroundColor] = theme.textColor

            out.append(NSAttributedString(string: "\(prefix)\t", attributes: currentAttributes))
            visitChildren(of: listItem)
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))

            currentAttributes = prev
        }
    }
}
