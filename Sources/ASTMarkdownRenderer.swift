import AppKit
import Foundation
import Markdown
import Highlightr

/// AST-based Markdown → NSAttributedString renderer (swift-markdown).
///
/// 目前採「能穩定處理的語法用 AST；遇到 GFM table/task/image 等就整份 fallback」策略，
/// 以便逐步導入 AST 而不破壞既有功能。
struct ASTMarkdownRenderer {
    let theme: NativeMarkdownTheme

    static func canRender(markdown: String) -> Bool {
        // swift-markdown 以 CommonMark 為主；本 repo 既有 native parser 已支援：
        // - pipe tables
        // - task lists
        // - images (NSTextAttachment)
        // 先採保守策略：一旦偵測到這些語法，交回既有 parser 全權處理。
        let s = markdown
        if s.contains("|") {
            // 粗略：若出現典型表格分隔線，就視為 table
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

            // 讓輸出尾端有一個換行（跟現有 native parser 行為一致，方便 textView layout）
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
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
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
            let attrs: [NSAttributedString.Key: Any] = [
                .font: theme.monoFont,
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
            // 用 NSTextBlock 做出引用視覺（與既有 native parser 一致概念）
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
            visitChildren(of: blockQuote)
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
            currentAttributes = prev
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            // Reader：先做 block 視覺 + mono font；語法高亮會在後續階段導入 Highlightr
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
            if let hl = Self.highlightr {
                hl.theme.setCodeFont(theme.monoFont)
                _ = hl.setTheme(to: (NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) ? "paraiso-dark" : "paraiso-light")
                let highlighted = hl.highlight(codeBlock.code, as: nil, fastRender: true)
                if let highlighted {
                    let m = NSMutableAttributedString(attributedString: highlighted)
                    m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
                    out.append(m)
                    out.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                    out.append(NSAttributedString(string: "\n", attributes: currentAttributes))
                    return
                }
            }

            out.append(NSAttributedString(string: codeBlock.code + "\n", attributes: baseAttrs))
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

            let (prefix, headIndent): (String, CGFloat)
            if let ctx = listStack.last {
                switch ctx {
                case .unordered(let depth):
                    let bullets = ["•", "◦", "▪", "▫"]
                    let bullet = bullets[depth % bullets.count]
                    prefix = "\(bullet) "
                    headIndent = 22 + CGFloat(depth) * 16
                case .ordered(let depth, let start):
                    let idx = start + listItem.indexInParent
                    prefix = "\(idx). "
                    headIndent = 26 + CGFloat(depth) * 16
                }
            } else {
                prefix = "• "
                headIndent = 22
            }

            let p = NSMutableParagraphStyle()
            p.firstLineHeadIndent = 0
            p.headIndent = headIndent
            p.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
            p.lineSpacing = theme.baseParagraphStyle.lineSpacing
            p.paragraphSpacing = 2

            currentAttributes[.paragraphStyle] = p
            currentAttributes[.font] = theme.paragraphFont
            currentAttributes[.foregroundColor] = theme.textColor

            out.append(NSAttributedString(string: prefix, attributes: currentAttributes))
            visitChildren(of: listItem)
            out.append(NSAttributedString(string: "\n", attributes: currentAttributes))

            currentAttributes = prev
        }
    }
}
