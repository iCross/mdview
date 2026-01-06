// NativeMarkdownView.swift
// macOS Markdown Viewer - Native NSTextView renderer

import AppKit
import Foundation
import Markdown
import Highlightr

enum NativeMarkdownPipeline: String {
    case regex = "regex"
    case ast = "ast"
}

/// Render Markdown using NSTextView with NSAttributedString.
/// Design goals: low resident cost, fast startup, no HTML/JS rendering dependency.
final class NativeMarkdownView: NSView, MarkdownRenderable {
    
    // MARK: - Properties
    
    weak var dropDelegate: MarkdownDropDelegate?
    
    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    
    private var currentZoomLevel: Double = 1.0
    private let zoomStep: Double = 0.1
    private let minZoom: Double = 0.5
    private let maxZoom: Double = 3.0
    
    private var lastMarkdownSource: String?
    private var isShowingWelcome: Bool = true
    private var documentURL: URL?
    private var pipeline: NativeMarkdownPipeline = .regex
    
    private var clipViewBoundsObserver: NSObjectProtocol?
    private var clipViewFrameObserver: NSObjectProtocol?
    private var remoteImageObserver: NSObjectProtocol?
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTextView()
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextView()
        registerForDraggedTypes([.fileURL])
    }
    
    deinit {
        if let o = clipViewBoundsObserver { NotificationCenter.default.removeObserver(o) }
        if let o = clipViewFrameObserver { NotificationCenter.default.removeObserver(o) }
        if let o = remoteImageObserver { NotificationCenter.default.removeObserver(o) }
    }
    
    // MARK: - Setup
    
    private func setupTextView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.isRichText = true
        textView.importsGraphics = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.textContainerInset = NSSize(width: 28, height: 22)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        
        scrollView.documentView = textView
        addSubview(scrollView)

        // Track content width with the view (natural wrapping for a native reader).
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
            // Notes-like: avoid TextKit's default padding affecting edges (we control margins via textContainerInset).
            container.lineFragmentPadding = 0
        }
        
        // Critical: documentView (NSTextView) needs an initial size; otherwise width can become tiny and wrap per character.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setFrameSize(scrollView.contentView.bounds.size)
        
        startObservingScrollViewGeometry()
        startObservingRemoteImages()
        syncTextContainerWidth()
    }

    override func layout() {
        super.layout()
        syncTextContainerWidth()
    }
    
    private func startObservingScrollViewGeometry() {
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        
        if clipViewBoundsObserver == nil {
            clipViewBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.syncTextContainerWidth()
            }
        }
        if clipViewFrameObserver == nil {
            clipViewFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.syncTextContainerWidth()
            }
        }
    }
    
    private func startObservingRemoteImages() {
        if remoteImageObserver != nil { return }
        remoteImageObserver = NotificationCenter.default.addObserver(
            forName: .mdviewerRemoteImageDidLoad,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Conservative strategy: after remote images load, trigger an attributes-edited pass + layout to refresh display.
            if let storage = self.textView.textStorage {
                let full = NSRange(location: 0, length: storage.length)
                storage.edited(.editedAttributes, range: full, changeInLength: 0)
            }
            self.syncTextContainerWidth()
            self.textView.layoutSubtreeIfNeeded()
            self.textView.displayIfNeeded()
        }
    }
    
    private func syncTextContainerWidth() {
        // Use the scrollView visible content width to avoid code blocks/tables becoming "one character wide".
        // Note: contentSize is closer to the actual usable width than bounds (excludes scroller occupancy, etc.).
        let visibleWidth = scrollView.contentSize.width
        let insetWidth = textView.textContainerInset.width
        let containerWidth = max(1, visibleWidth - insetWidth * 2)
        guard containerWidth > 1 else { return }
        
        // Keep the textView itself at a reasonable width.
        var frame = textView.frame
        if abs(frame.width - visibleWidth) > 0.5 {
            frame.size.width = visibleWidth
            textView.frame = frame
        }
        
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            
            // Force the layout manager to reflow with new geometry (fix "it got wider but still wraps per character").
            textView.layoutManager?.textContainerChangedGeometry(container)
        }
    }
    
    // MARK: - MarkdownRenderable

    func setDocumentURL(_ url: URL?) {
        documentURL = url
    }

    func setPipeline(_ pipeline: NativeMarkdownPipeline) {
        self.pipeline = pipeline
    }
    
    func renderMarkdown(_ content: String) {
        lastMarkdownSource = content
        isShowingWelcome = false
        
        let theme = NativeMarkdownTheme(zoom: currentZoomLevel)
        let baseURL = documentURL?.deletingLastPathComponent()
        let attributed: NSAttributedString
        if pipeline == .ast, ASTMarkdownRenderer.canRender(markdown: content) {
            attributed = ASTMarkdownRenderer(theme: theme).render(markdown: content)
        } else {
            let maxTableWidth = textView.textContainer?.containerSize.width
            attributed = NativeMarkdownParser(theme: theme, baseURL: baseURL, maxTableWidth: maxTableWidth).render(markdown: content)
        }
        
        // Put the result into textStorage
        textView.textStorage?.setAttributedString(attributed)

        // Ensure the first render reflows with the correct container width (tables/code blocks often regress here).
        syncTextContainerWidth()
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        
        // Scroll to top
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    
    func loadWelcomePage() {
        lastMarkdownSource = nil
        isShowingWelcome = true
        
        let theme = NativeMarkdownTheme(zoom: currentZoomLevel)
        let welcome = """
        # Markdown Viewer
        
        A lightweight macOS Markdown viewer (native rendering).
        
        ## Getting started
        
        - Drag and drop a `.md` / `.markdown` file into this window
        - Or use the menu `File → Open…` to open a file
        - Or use the command line: `./mdview path/to/file.md`
        """
        
        let maxTableWidth = textView.textContainer?.containerSize.width
        let attributed = NativeMarkdownParser(theme: theme, baseURL: nil, maxTableWidth: maxTableWidth).render(markdown: welcome)
        textView.textStorage?.setAttributedString(attributed)
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    
    // MARK: - Zoom Methods
    
    func zoomIn() {
        currentZoomLevel = min(currentZoomLevel + zoomStep, maxZoom)
        rerenderForZoomChange()
    }
    
    func zoomOut() {
        currentZoomLevel = max(currentZoomLevel - zoomStep, minZoom)
        rerenderForZoomChange()
    }
    
    func resetZoom() {
        currentZoomLevel = 1.0
        rerenderForZoomChange()
    }

    func rerender() {
        rerenderForZoomChange()
    }
    
    private func rerenderForZoomChange() {
        if isShowingWelcome {
            loadWelcomePage()
            return
        }
        if let source = lastMarkdownSource {
            renderMarkdown(source)
        }
    }
    
    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let types = sender.draggingPasteboard.types,
              types.contains(.fileURL) else {
            return []
        }
        
        if let fileURL = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                return .copy
            }
        }
        return []
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let fileURL = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL else {
            return false
        }
        
        let ext = fileURL.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            dropDelegate?.markdownView(self, didReceiveDroppedFile: fileURL.path)
            return true
        }
        return false
    }
    
    // MARK: - CLI debug / tests
    
    /// Print testable parse/debug output without launching the GUI (used by `--dump`).
    static func debugDump(markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        var out: [String] = []
        let imageRegex = try? NSRegularExpression(pattern: "!\\[([^\\]]*?)\\]\\(([^\\)]+?)\\)", options: [])
        var inCodeFence = false
        var codeFenceLanguage = ""
        var codeBuffer: [String] = []
        var i = 0
        while i < lines.count {
            // Fenced code block (debug): keep original text; for mermaid fences, also emit a diagram URL after closing.
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCodeFence {
                    // close
                    out.append(line)
                    if codeFenceLanguage == "mermaid" {
                        let code = codeBuffer.joined(separator: "\n")
                        // Keep legacy format (backward-compatible with tests).
                        if let url = MermaidRenderer.makeDiagramURL(code: code, appearance: nil) {
                            out.append("[[MERMAID_URL]] \(url.absoluteString)")
                        } else {
                            out.append("[[MERMAID_URL]] (invalid)")
                        }
                        // Also emit comparison info (useful for manual inspection).
                        if let comparison = MermaidRenderer.makeDiagramURLComparison(code: code, appearance: nil) {
                            out.append("[[MERMAID_URL_COMPARISON]]")
                            out.append(comparison)
                        }
                    }
                    inCodeFence = false
                    codeFenceLanguage = ""
                    codeBuffer.removeAll(keepingCapacity: true)
                    i += 1
                    continue
                } else {
                    // open
                    out.append(line)
                    inCodeFence = true
                    codeFenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    codeBuffer.removeAll(keepingCapacity: true)
                    i += 1
                    continue
                }
            }
            if inCodeFence {
                out.append(line)
                codeBuffer.append(line)
                i += 1
                continue
            }

            if i + 1 < lines.count, NativeMarkdownParser.looksLikeTableHeaderStatic(lines[i], separatorLine: lines[i + 1]) {
                let (header, rows, consumed) = NativeMarkdownParser.parseTableStatic(from: lines, startIndex: i)
                out.append("[[TABLE]] " + header.joined(separator: " | "))
                for row in rows {
                    out.append("[[ROW]] " + row.joined(separator: " | "))
                }
                i += consumed
                continue
            }

            if let imageRegex {
                let matches = imageRegex.matches(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length))
                for m in matches {
                    guard m.numberOfRanges >= 3 else { continue }
                    let alt = (line as NSString).substring(with: m.range(at: 1))
                    let url = (line as NSString).substring(with: m.range(at: 2))
                    out.append("[[IMAGE]] \(alt) | \(url)")
                }
            }
            out.append(line)
            i += 1
        }
        
        return out.joined(separator: "\n")
    }
    
    /// Print rendered plain text without launching the GUI (used to verify content after fenced code blocks isn't dropped).
    static func debugRenderPlainText(markdown: String, pipeline: NativeMarkdownPipeline = .regex) -> String {
        let theme = NativeMarkdownTheme(zoom: 1.0)
        let attributed: NSAttributedString
        if pipeline == .ast, ASTMarkdownRenderer.canRender(markdown: markdown) {
            attributed = ASTMarkdownRenderer(theme: theme).render(markdown: markdown)
        } else {
            attributed = NativeMarkdownParser(theme: theme, baseURL: nil, maxTableWidth: nil).render(markdown: markdown)
        }
        // The renderer may use U+2028 (line separator) to avoid paragraph-spacing issues.
        // For debug/tests, normalize back to "\n" for string comparisons and terminal inspection.
        return attributed.string.replacingOccurrences(of: "\u{2028}", with: "\n")
    }

    /// Verify NSTextView/NSScrollView width skeleton without launching the GUI (used by `--skeleton-check`).
    /// Goal: prevent regressions to per-character wrapping (often caused by the text container width being synced to a tiny value).
    static func debugSkeletonCheck() -> String {
        // Initialize NSApplication for safety (even if we don't enter the event loop).
        _ = NSApplication.shared

        let view = NativeMarkdownView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        view.loadWelcomePage()

        // Simulate window width changes (common trigger: scrollbar/clipView bounds changes).
        let widths: [CGFloat] = [900, 600, 360, 820]
        var rows: [String] = []

        var ok = true
        for w in widths {
            view.frame = NSRect(x: 0, y: 0, width: w, height: 700)
            view.layoutSubtreeIfNeeded()
            view.syncTextContainerWidth()

            let visibleWidth = view.scrollView.contentSize.width
            let insetWidth = view.textView.textContainerInset.width
            let expected = max(1, visibleWidth - insetWidth * 2)
            let actual = view.textView.textContainer?.containerSize.width ?? -1

            rows.append(String(format: "width=%.0f visible=%.2f inset=%.2f expected=%.2f actual=%.2f", w, visibleWidth, insetWidth, expected, actual))

            // Allow small tolerance (floating point/layout timing).
            if !(actual > 50 && abs(actual - expected) < 3.0) {
                ok = false
            }
        }

        if ok {
            return "SKELETON_OK\n" + rows.joined(separator: "\n")
        } else {
            return "SKELETON_FAIL\n" + rows.joined(separator: "\n")
        }
    }

    // MARK: - Screenshot helpers (for AppDelegate automation)

    /// Scroll to the first occurrence of the given text (used by `--screenshot-scroll-to`).
    /// - Returns: Whether the text was found and scrolling succeeded
    func scrollToFirstOccurrence(of text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }

        let haystack = textView.string
        guard let r = haystack.range(of: needle) else { return false }
        let nsRange = NSRange(r, in: haystack)
        textView.scrollRangeToVisible(nsRange)
        return true
    }

    /// Scroll to a y offset in points (0 = top of document).
    func scrollTo(y: CGFloat) {
        let doc = scrollView.documentView ?? textView
        let viewportHeight = scrollView.contentSize.height
        let maxOffset = max(0, doc.bounds.height - viewportHeight)
        let requested = max(0, y)

        let targetY: CGFloat
        if doc.isFlipped {
            targetY = min(requested, maxOffset)
        } else {
            // If the coordinate system is not flipped, convert "from top" to "from bottom".
            targetY = min(max(0, maxOffset - requested), maxOffset)
        }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Return the view used for full-page screenshots (documentView).
    /// Currently returns the NSTextView itself (its frame height grows with content).
    func viewForFullScreenshot() -> NSView {
        // Ensure layout is complete and expand textView height to fit the full content (avoid capturing only the first screen).
        if let container = textView.textContainer, let lm = textView.layoutManager {
            lm.ensureLayout(for: container)
            let used = lm.usedRect(for: container)
            let inset = textView.textContainerInset
            let desiredHeight = max(scrollView.contentSize.height, used.height + inset.height * 2)
            if abs(textView.frame.height - desiredHeight) > 1.0 {
                var f = textView.frame
                f.size.height = desiredHeight
                textView.frame = f
            }
        }
        textView.layoutSubtreeIfNeeded()
        textView.displayIfNeeded()
        return textView
    }
}

// MARK: - Theme

struct NativeMarkdownTheme {
    let zoom: Double
    
    // Base font sizes (multiplied by zoom).
    var baseFontSize: CGFloat { CGFloat(16.0 * zoom) }
    var codeFontSize: CGFloat { CGFloat(13.5 * zoom) }
    
    var paragraphFont: NSFont { NSFont.systemFont(ofSize: baseFontSize) }
    var boldFont: NSFont { NSFont.systemFont(ofSize: baseFontSize, weight: .semibold) }
    var italicFont: NSFont { NSFontManager.shared.convert(paragraphFont, toHaveTrait: .italicFontMask) }
    
    func headingFont(level: Int) -> NSFont {
        let scale: CGFloat
        switch level {
        case 1: scale = 1.9
        case 2: scale = 1.55
        case 3: scale = 1.3
        case 4: scale = 1.15
        case 5: scale = 1.05
        default: scale = 1.0
        }
        return NSFont.systemFont(ofSize: baseFontSize * scale, weight: .bold)
    }
    
    var monoFont: NSFont { NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular) }
    
    /// For inline code: follow the current font size (avoid inline code looking tiny in headings/large text).
    func monoFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    // Notes-like paragraph style (reader-focused: consistent line height and paragraph spacing).
    var baseParagraphStyle: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.22
        p.lineSpacing = 2
        p.paragraphSpacing = 8
        p.paragraphSpacingBefore = 0
        p.hyphenationFactor = 0
        p.lineBreakMode = .byWordWrapping
        return p
    }

    func headingParagraphStyle(level: Int) -> NSParagraphStyle {
        let p = baseParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
        // Headings: add a bit more breathing room.
        switch level {
        case 1:
            p.paragraphSpacing = 12
        case 2:
            p.paragraphSpacing = 10
        default:
            p.paragraphSpacing = 8
        }
        return p
    }
    
    // Dynamic colors (follow light/dark appearance).
    var textColor: NSColor { .textColor }
    var secondaryTextColor: NSColor { .secondaryLabelColor }
    var linkColor: NSColor { .linkColor }
    var codeBackgroundColor: NSColor { NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(calibratedWhite: 0.12, alpha: 1.0) : NSColor(calibratedWhite: 0.96, alpha: 1.0)
    } }
    var codeBorderColor: NSColor { NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(calibratedWhite: 0.22, alpha: 1.0) : NSColor(calibratedWhite: 0.86, alpha: 1.0)
    } }
}

// MARK: - Parser / Renderer

/// Minimal Markdown → NSAttributedString renderer:
/// - Supports: headings, paragraphs, blockquotes, lists, tasks, horizontal rules, inline code, bold/italic/strikethrough, links, fenced code blocks (with basic regex highlighting)
private final class NativeMarkdownParser {
    
    private let theme: NativeMarkdownTheme
    private let baseURL: URL?
    /// Max width for native tables (in points). If nil, use a conservative default.
    /// - Purpose: small tables can size to content; very wide content shouldn't create a massive table (wrap/auto-layout instead).
    private let maxTableWidth: CGFloat?
    
    // Custom attribute: used to avoid applying bold/italic rules inside code spans.
    private static let isCodeAttribute = NSAttributedString.Key("NativeMarkdownIsCode")
    
    init(theme: NativeMarkdownTheme, baseURL: URL?, maxTableWidth: CGFloat? = nil) {
        self.theme = theme
        self.baseURL = baseURL
        self.maxTableWidth = maxTableWidth
    }
    
    func render(markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        var inCodeFence = false
        var codeFenceLanguage: String = ""
        var codeBuffer: [String] = []
        
        func flushParagraph(_ text: String) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: theme.paragraphFont,
                .foregroundColor: theme.textColor,
                .paragraphStyle: theme.baseParagraphStyle
            ]
            output.append(formatInline(text, baseAttributes: attrs))
            // Paragraph spacing is controlled by paragraphStyle.paragraphSpacing; only append a single newline here.
            output.append(NSAttributedString(string: "\n"))
        }
        
        var pendingParagraphLines: [String] = []
        func flushPendingParagraph() {
            guard !pendingParagraphLines.isEmpty else { return }
            flushParagraph(pendingParagraphLines.joined(separator: "\n"))
            pendingParagraphLines.removeAll(keepingCapacity: true)
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // fenced code block
            if trimmed.hasPrefix("```") {
                if inCodeFence {
                    // close
                    flushPendingParagraph()
                    output.append(renderCodeBlock(codeBuffer.joined(separator: "\n"), language: codeFenceLanguage))
                    output.append(NSAttributedString(string: "\n"))
                    inCodeFence = false
                    codeFenceLanguage = ""
                    codeBuffer.removeAll(keepingCapacity: true)
                    // Important: consume the closing fence line; otherwise the next loop may treat it as an opening fence.
                    i += 1
                    continue
                } else {
                    // open
                    flushPendingParagraph()
                    inCodeFence = true
                    codeFenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    i += 1
                    continue
                }
            }
            
            if inCodeFence {
                codeBuffer.append(line)
                i += 1
                continue
            }
            
            // Blank line: end the paragraph
            if trimmed.isEmpty {
                flushPendingParagraph()
                i += 1
                continue
            }
            
            // Horizontal rule
            if trimmed == "---" || trimmed == "----" || trimmed == "-----" {
                flushPendingParagraph()
                output.append(renderHorizontalRule())
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // Heading (# ~ ######)
            if let heading = parseHeading(line) {
                flushPendingParagraph()
                output.append(renderHeading(level: heading.level, text: heading.text))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // Blockquote (>): parse consecutive quote lines as a block to avoid per-line blocks stacking paragraphSpacing.
            if looksLikeBlockquoteStart(line) {
                flushPendingParagraph()
                let (quoteText, consumed) = parseBlockquoteBlock(from: lines, startIndex: i)
                if !quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output.append(renderBlockquote(quoteText))
                    output.append(NSAttributedString(string: "\n"))
                }
                i += consumed
                continue
            }

            // Table (GitHub-style pipe table)
            if i + 1 < lines.count, looksLikeTableHeader(lines[i], separatorLine: lines[i + 1]) {
                flushPendingParagraph()
                let (table, consumed) = parseTable(from: lines, startIndex: i)
                output.append(renderTable(table))
                output.append(NSAttributedString(string: "\n"))
                i += consumed
                continue
            }
            
            // Task list / unordered list (supports multi-level indentation)
            if let task = parseTaskListItem(line) {
                flushPendingParagraph()
                output.append(renderListItem(prefix: task.checked ? "☑︎" : "☐", text: task.text, depth: task.depth))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            if let bullet = parseBulletListItem(line) {
                flushPendingParagraph()
                output.append(renderListItem(prefix: "•", text: bullet.text, depth: bullet.depth))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // Ordered list (1.)
            if let ordered = parseOrderedListItem(line) {
                flushPendingParagraph()
                // Ordered list: align with "." + tab (Notes-like).
                output.append(renderListItem(prefix: "\(ordered.index).", text: ordered.text, depth: ordered.depth))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // Other: accumulate into a paragraph
            pendingParagraphLines.append(line)
            i += 1
        }
        
        // flush remaining
        flushPendingParagraph()
        
        // If the document ends with a list, avoid extra trailing whitespace; leaving it is fine (NSTextView tolerates it).
        return output
    }
    
    // MARK: - Block Parsers
    
    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        // e.g. "### Title"
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard hashes >= 1 && hashes <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return (hashes, text)
    }
    
    private func looksLikeBlockquoteStart(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private func parseBlockquoteBlock(from lines: [String], startIndex: Int) -> (text: String, consumed: Int) {
        var quoteLines: [String] = []
        var i = startIndex
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }

            var rest = trimmed.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
            let content = String(rest) // may be an empty string (corresponds to a `>` blank line)
            quoteLines.append(content)
            i += 1
        }

        // Normalize: within the same paragraph, join lines using U+2028 (line separator) so they aren't treated as new paragraphs.
        // A `>` blank line represents a paragraph break; separate paragraphs with \n\n.
        var paragraphs: [String] = []
        var current: [String] = []
        var sawBlank = false
        for l in quoteLines {
            if l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sawBlank = true
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: "\u{2028}"))
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            if sawBlank {
                sawBlank = false
            }
            current.append(l)
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: "\u{2028}"))
        }

        let text = paragraphs.joined(separator: "\n\n")
        return (text, i - startIndex)
    }
    
    private func listIndentDepth(_ line: String) -> Int {
        // Simplified nested list support focused on "visual indentation":
        // - 2 spaces per level (supports many levels)
        // - tab counts as 4 spaces
        var spaces = 0
        for ch in line {
            if ch == " " {
                spaces += 1
            } else if ch == "\t" {
                spaces += 4
            } else {
                break
            }
        }
        return min(20, max(0, spaces / 2))
    }

    private func parseTaskListItem(_ line: String) -> (depth: Int, checked: Bool, text: String)? {
        // "- [x] text" / "- [ ] text"
        let depth = listIndentDepth(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") || trimmed.hasPrefix("+ [") else { return nil }
        guard trimmed.count >= 6 else { return nil }
        let chars = Array(trimmed)
        // "- [x]" -> indices: 0 '-' 1 ' ' 2 '[' 3 'x' 4 ']'
        guard chars.count >= 5, chars[1] == " ", chars[2] == "[", chars[4] == "]" else { return nil }
        let mark = chars[3]
        let checked = (mark == "x" || mark == "X")
        let start = 5
        let text = String(chars.dropFirst(start)).trimmingCharacters(in: .whitespaces)
        return (depth, checked, text)
    }
    
    private func parseBulletListItem(_ line: String) -> (depth: Int, text: String)? {
        // "- text" "* text" "+ text" / "• text"
        let depth = listIndentDepth(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("•\t") else { return nil }
        if trimmed.hasPrefix("•") {
            return (depth, String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
        }
        return (depth, String(trimmed.dropFirst(2)))
    }
    
    private func parseOrderedListItem(_ line: String) -> (depth: Int, index: Int, text: String)? {
        // "1. text" (with indentation)
        let depth = listIndentDepth(line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let numberPart = trimmed[..<dotIndex]
        guard let n = Int(numberPart), n >= 1 else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        let text = afterDot.trimmingCharacters(in: .whitespaces)
        return (depth, n, text)
    }
    
    // MARK: - Block Renderers
    
    private func renderHeading(level: Int, text: String) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.headingFont(level: level),
            .foregroundColor: theme.textColor,
            .paragraphStyle: theme.headingParagraphStyle(level: level)
        ]
        return formatInline(text, baseAttributes: attrs)
    }
    
    private func renderBlockquote(_ text: String) -> NSAttributedString {
        // Use NSTextBlock for native blockquote styling (left border + padding).
        let block = NSTextBlock()
        block.backgroundColor = NSColor.clear
        // Important: make the block fill available width (otherwise it can become extremely narrow).
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(theme.codeBorderColor, for: .minX)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.textBlocks = [block]
        paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
        paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = 10
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.paragraphFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let out = NSMutableAttributedString(attributedString: formatInline(text, baseAttributes: attrs))
        // Ensure the entire string (including \n) uses the blockquote paragraphStyle.
        if out.length > 0 {
            out.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: out.length))
        }
        return out
    }
    
    private func renderListItem(prefix: String, text: String, depth: Int = 0) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        // Notes.app style: use a tab stop to create a hanging indent with prefix on the left and aligned text.
        // - prefix then \t
        // - text starts from the tab stop
        let d = min(20, max(0, depth))
        let depthIndent = CGFloat(d) * 16
        let bulletIndent: CGFloat = 14 + depthIndent
        let prefixWidth = (prefix as NSString).size(withAttributes: [.font: theme.paragraphFont]).width
        let minTextIndent: CGFloat = 32 + depthIndent
        let textIndent = max(minTextIndent, bulletIndent + prefixWidth + 12)
        
        // First line: indent prefix to bulletIndent; use tab to jump text to textIndent.
        paragraphStyle.firstLineHeadIndent = bulletIndent
        // Subsequent lines align with text start (hanging indent).
        paragraphStyle.headIndent = textIndent
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .left, location: textIndent, options: [:])
        ]
        paragraphStyle.defaultTabInterval = textIndent
        paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
        paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = 2
        
        let base: [NSAttributedString.Key: Any] = [
            .font: theme.paragraphFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        // Don't include trailing spaces in prefix; use \t so the text aligns to the tab stop.
        let out = NSMutableAttributedString(string: "\(prefix)\t", attributes: base)
        out.append(formatInline(text, baseAttributes: base))
        return out
    }
    
    private func renderHorizontalRule() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
        paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = 10
        paragraphStyle.lineBreakMode = .byClipping

        // Use a long horizontal line; clipping prevents wrap on narrow widths.
        return NSAttributedString(string: String(repeating: "─", count: 100), attributes: [
            .font: theme.paragraphFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle
        ])
    }
    
    private func renderCodeBlock(_ code: String, language: String) -> NSAttributedString {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Use NSTextBlock for a native code block (background + padding + border).
        let block = NSTextBlock()
        block.backgroundColor = theme.codeBackgroundColor
        // Important: make the block fill available width (avoid a "one character wide" code block).
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(theme.codeBorderColor)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.textBlocks = [block]
        paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
        paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = 10
        
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ]

        // Prefer Highlightr (highlight.js via JavaScriptCore); fall back to regex on failure.
        let codeOut: NSMutableAttributedString
        if let highlighted = NativeHighlightr.highlight(code: code, languageHint: language, theme: theme) {
            codeOut = NSMutableAttributedString(attributedString: highlighted)
            codeOut.append(NSAttributedString(string: "\n", attributes: baseAttrs))
        } else {
            codeOut = NSMutableAttributedString(string: code + "\n", attributes: baseAttrs)
            NativeCodeHighlighter.applyRegexHighlight(to: codeOut, languageHint: language, theme: theme)
        }
        
        // Mark as code (avoid later inline rules overriding it).
        let codeRange = NSRange(location: 0, length: codeOut.length)
        codeOut.addAttribute(Self.isCodeAttribute, value: true, range: codeRange)
        codeOut.addAttribute(.paragraphStyle, value: paragraphStyle, range: codeRange)

        // Mermaid: keep the code block and insert a diagram below (mermaid.ink; non-blocking load).
        let out = NSMutableAttributedString(attributedString: codeOut)
        if lang == "mermaid" {
            let maxW = maxTableWidth
            if let diagram = MermaidRenderer.makeAttachment(code: code, theme: theme, maxWidth: maxW) {
                let p = NSMutableParagraphStyle()
                p.alignment = .center
                p.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
                p.lineSpacing = theme.baseParagraphStyle.lineSpacing
                p.paragraphSpacing = 10
                p.paragraphSpacingBefore = 4
                p.lineBreakMode = .byWordWrapping

                let diagramOut = NSMutableAttributedString(attributedString: diagram)
                let r = NSRange(location: 0, length: diagramOut.length)
                diagramOut.addAttributes([
                    .font: theme.paragraphFont,
                    .foregroundColor: theme.textColor,
                    .paragraphStyle: p
                ], range: r)
                out.append(diagramOut)
            }
        }

        return out
    }

    // MARK: - Tables

    private struct ParsedTable {
        let header: [String]
        let rows: [[String]]
    }

    // MARK: - Tables (instance + static helpers for CLI debug)
    
    static func looksLikeTableHeaderStatic(_ headerLine: String, separatorLine: String) -> Bool {
        // header: contains |, separator: --- / :---: style
        let headerTrimmed = headerLine.trimmingCharacters(in: .whitespaces)
        let sepTrimmed = separatorLine.trimmingCharacters(in: .whitespaces)
        guard headerTrimmed.contains("|") else { return false }
        
        // e.g. | --- | :---: | ---: |
        let pattern = #"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: (sepTrimmed as NSString).length)
        return regex.firstMatch(in: sepTrimmed, options: [], range: range) != nil
    }
    
    static func parseTableStatic(from lines: [String], startIndex: Int) -> (header: [String], rows: [[String]], consumed: Int) {
        let headerLine = lines[startIndex]
        let header = splitTableRowStatic(headerLine)
        var rows: [[String]] = []
        
        var i = startIndex + 2
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if !trimmed.contains("|") { break }
            rows.append(splitTableRowStatic(line))
            i += 1
        }
        
        return (header, rows, i - startIndex)
    }
    
    private static func splitTableRowStatic(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        
        return s
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    private func looksLikeTableHeader(_ headerLine: String, separatorLine: String) -> Bool {
        // header: contains |, separator: --- / :---: style
        let headerTrimmed = headerLine.trimmingCharacters(in: .whitespaces)
        let sepTrimmed = separatorLine.trimmingCharacters(in: .whitespaces)
        guard headerTrimmed.contains("|") else { return false }

        // e.g. | --- | :---: | ---: |
        let pattern = #"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: (sepTrimmed as NSString).length)
        return regex.firstMatch(in: sepTrimmed, options: [], range: range) != nil
    }

    private func parseTable(from lines: [String], startIndex: Int) -> (ParsedTable, consumed: Int) {
        let headerLine = lines[startIndex]
        let separatorLine = lines[startIndex + 1]
        _ = separatorLine // we only use it as a guard

        let header = splitTableRow(headerLine)
        var rows: [[String]] = []

        var i = startIndex + 2
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if !trimmed.contains("|") { break }
            // If we hit another syntax (e.g. a list), stop table parsing.
            if parseTaskListItem(line) != nil || parseBulletListItem(line) != nil || parseOrderedListItem(line) != nil {
                break
            }
            rows.append(splitTableRow(line))
            i += 1
        }

        let table = ParsedTable(header: header, rows: rows)
        return (table, i - startIndex)
    }

    private func splitTableRow(_ line: String) -> [String] {
        // Supports:
        // - | a | b |
        // - a | b
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }

        return s
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func renderTable(_ table: ParsedTable) -> NSAttributedString {
        // Use NSTextTable/NSTextTableBlock to produce a real table layout (NSTextView performs cell layout).
        let allRows = [table.header] + table.rows
        let colCount = allRows.map(\.count).max() ?? 0
        guard colCount > 0 else { return NSAttributedString(string: "") }

        let textTable = NSTextTable()
        textTable.numberOfColumns = colCount
        // Content-driven: small tables don't force-fill the window (avoid huge empty space in each column).
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let out = NSMutableAttributedString()

        // Estimate column widths: measure text to make content-driven tables more compact.
        func measure(_ s: String, font: NSFont) -> CGFloat {
            let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return 0 }
            return (text as NSString).size(withAttributes: [.font: font]).width
        }

        // Cell padding / border (must match block settings below).
        let cellPadding: CGFloat = 6
        let cellBorder: CGFloat = 1
        let cellExtra: CGFloat = cellPadding * 2 + cellBorder * 2 + 8  // extra to avoid tight fit

        var colWidths = Array(repeating: CGFloat(0), count: colCount)
        for (rIndex, row) in allRows.enumerated() {
            for c in 0..<colCount {
                let text = (c < row.count) ? row[c] : ""
                let font = (rIndex == 0) ? theme.boldFont : theme.paragraphFont
                colWidths[c] = max(colWidths[c], measure(text, font: font))
            }
        }
        for c in 0..<colCount {
            colWidths[c] += cellExtra
        }

        let intrinsicWidth = colWidths.reduce(0, +)
        let maxWidth = maxTableWidth ?? CGFloat(900.0 * theme.zoom)
        let useFixedColumns = intrinsicWidth > 0 && intrinsicWidth <= maxWidth

        if useFixedColumns {
            // Small table: size the whole table by intrinsic content width.
            textTable.setContentWidth(intrinsicWidth, type: .absoluteValueType)
        } else {
            // Very wide table: cap max width and let TextKit handle layout + wrapping.
            textTable.setContentWidth(maxWidth, type: .absoluteValueType)
        }

        func makeCellParagraph(
            row: Int,
            col: Int,
            text: String,
            isHeader: Bool
        ) -> NSAttributedString {
            let block = NSTextTableBlock(
                table: textTable,
                startingRow: row,
                rowSpan: 1,
                startingColumn: col,
                columnSpan: 1
            )

            // padding / border
            block.setWidth(6, type: .absoluteValueType, for: .padding)
            block.setWidth(1, type: .absoluteValueType, for: .border)
            block.setBorderColor(theme.codeBorderColor)
            block.backgroundColor = isHeader ? theme.codeBackgroundColor : NSColor.clear
            block.verticalAlignment = .topAlignment
            if useFixedColumns, col < colWidths.count {
                // Small table: each column uses the measured fixed width.
                block.setContentWidth(colWidths[col], type: .absoluteValueType)
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.textBlocks = [block]
            paragraphStyle.paragraphSpacing = 0
            paragraphStyle.paragraphSpacingBefore = 0
            paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
            paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
            paragraphStyle.lineBreakMode = .byWordWrapping

            let base: [NSAttributedString.Key: Any] = [
                .font: isHeader ? theme.boldFont : theme.paragraphFont,
                .foregroundColor: theme.textColor,
                .paragraphStyle: paragraphStyle
            ]

            // Allow simple inline formatting inside cells (bold/link/inline code, etc.).
            let content = NSMutableAttributedString(attributedString: formatInline(text, baseAttributes: base))
            content.append(NSAttributedString(string: "\n", attributes: base))
            content.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: content.length))
            return content
        }

        // header row
        for c in 0..<colCount {
            let cellText = (c < table.header.count) ? table.header[c] : ""
            out.append(makeCellParagraph(row: 0, col: c, text: cellText, isHeader: true))
        }

        // body rows
        for (rIndex, row) in table.rows.enumerated() {
            for c in 0..<colCount {
                let cellText = (c < row.count) ? row[c] : ""
                out.append(makeCellParagraph(row: rIndex + 1, col: c, text: cellText, isHeader: false))
            }
        }

        // Add spacing after the table (outer layer also adds \n\n; this avoids table block sticking to the next paragraph).
        out.append(NSAttributedString(string: "\n"))
        return out
    }
    
    // MARK: - Inline Formatting
    
    private func formatInline(_ text: String, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
        
        // images：![alt](url)
        applyInlineImages(in: attributed, baseAttributes: baseAttributes)
        
        // Special case: **`code`** (bold code span) - handle before regular code spans and bold
        if let regex = try? NSRegularExpression(pattern: "\\*\\*`([^`]+)`\\*\\*", options: []) {
            let s = attributed.string
            let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let fullRange = match.range(at: 0)
                let codeRange = match.range(at: 1)
                if fullRange.location == NSNotFound || codeRange.location == NSNotFound { continue }
                
                let codeText = (s as NSString).substring(with: codeRange)
                let baseFont = (baseAttributes[.font] as? NSFont) ?? theme.paragraphFont
                attributed.replaceCharacters(in: fullRange, with: codeText)
                let newRange = NSRange(location: fullRange.location, length: (codeText as NSString).length)
                attributed.addAttributes([
                    .font: theme.monoFont(ofSize: baseFont.pointSize, weight: .semibold),
                    .backgroundColor: theme.codeBackgroundColor,
                    .foregroundColor: theme.textColor,
                    Self.isCodeAttribute: true
                ], range: newRange)
            }
        }
        
        // code span：`code` (regular, not bold)
        applyInlinePattern(
            pattern: "`([^`]+)`",
            in: attributed,
            replaceWithCapture: 1
        ) { range in
            let baseFont = (baseAttributes[.font] as? NSFont) ?? theme.paragraphFont
            attributed.addAttributes([
                .font: theme.monoFont(ofSize: baseFont.pointSize),
                .backgroundColor: theme.codeBackgroundColor,
                .foregroundColor: theme.textColor,
                Self.isCodeAttribute: true
            ], range: range)
        }
        
        // bold：**text** / __text__ (skip code spans)
        applyInlinePattern(
            pattern: "\\*\\*(.+?)\\*\\*",
            in: attributed,
            replaceWithCapture: 1,
            skipIfInsideCode: true
        ) { range in
            attributed.addAttributes([.font: theme.boldFont], range: range)
        }
        applyInlinePattern(
            pattern: "__(.+?)__",
            in: attributed,
            replaceWithCapture: 1,
            skipIfInsideCode: true
        ) { range in
            attributed.addAttributes([.font: theme.boldFont], range: range)
        }
        
        // links：[text](url)
        applyInlinePattern(
            pattern: "\\[([^\\]]+?)\\]\\(([^\\)]+?)\\)",
            in: attributed,
            replaceWithCapture: 1
        ) { range, captures in
            // captures[2] is URL
            if captures.count >= 3 {
                let urlString = captures[2]
                attributed.addAttributes([
                    .link: urlString,
                    .foregroundColor: theme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: range)
            }
        }
        
        // strikethrough：~~text~~
        applyInlinePattern(
            pattern: "~~(.+?)~~",
            in: attributed,
            replaceWithCapture: 1,
            skipIfInsideCode: true
        ) { range in
            attributed.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: range)
        }
        
        // italic：*text* / _text_
        // Conservative rule to avoid mis-detecting list markers as italics: require at least 2 characters of content.
        applyInlinePattern(
            pattern: "(?<!\\*)\\*(.{2,}?)\\*(?!\\*)",
            in: attributed,
            replaceWithCapture: 1,
            skipIfInsideCode: true
        ) { range in
            attributed.addAttributes([.font: theme.italicFont], range: range)
        }
        applyInlinePattern(
            pattern: "(?<!_)_(.{2,}?)_(?!_)",
            in: attributed,
            replaceWithCapture: 1,
            skipIfInsideCode: true
        ) { range in
            attributed.addAttributes([.font: theme.italicFont], range: range)
        }
        
        return attributed
    }

    private func applyInlineImages(in attributed: NSMutableAttributedString, baseAttributes: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: "!\\[([^\\]]*?)\\]\\(([^\\)]+?)\\)", options: []) else { return }
        
        let s = attributed.string
        let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
        guard !matches.isEmpty else { return }
        
        for match in matches.reversed() {
            let fullRange = match.range(at: 0)
            let altRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            if fullRange.location == NSNotFound || urlRange.location == NSNotFound { continue }
            
            let altText = (altRange.location == NSNotFound) ? "" : (s as NSString).substring(with: altRange)
            let rawURL = (s as NSString).substring(with: urlRange)
            let urlString = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let url = resolveResourceURL(urlString) {
                // Remote images: non-blocking load (avoid UI stalls / slow startup).
                if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    let maxWidth: CGFloat = CGFloat(720.0 * theme.zoom)
                    let attachment = RemoteImageAttachment(url: url, maxWidth: maxWidth, zoom: theme.zoom)
                    attachment.startIfNeeded()

                    let imgString = NSMutableAttributedString(attachment: attachment)
                    // Make the image clickable (if NSTextView supports links on attachments).
                    imgString.addAttribute(.link, value: url.absoluteString, range: NSRange(location: 0, length: imgString.length))
                    attributed.replaceCharacters(in: fullRange, with: imgString)
                    continue
                }

                // Local images: load synchronously (fast file IO; no network).
                if let image = NSImage(contentsOf: url) {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    
                    // Scale to a reasonable max width to avoid huge images breaking layout.
                    let maxWidth: CGFloat = CGFloat(720.0 * theme.zoom)
                    let size = image.size
                    if size.width > 0 && size.height > 0 {
                        let ratio = min(1.0, maxWidth / size.width)
                        let displaySize = NSSize(width: size.width * ratio, height: size.height * ratio)
                        attachment.bounds = NSRect(x: 0, y: 0, width: displaySize.width, height: displaySize.height)
                    }
                    
                    let imgString = NSAttributedString(attachment: attachment)
                    attributed.replaceCharacters(in: fullRange, with: imgString)
                    continue
                }
            } else {
                // Fallback: show alt text (or "Image") and attach a link if possible.
                let label = altText.isEmpty ? "Image" : altText
                let fallback = NSMutableAttributedString(string: label, attributes: baseAttributes)
                if let url = URL(string: urlString), url.scheme != nil {
                    fallback.addAttributes([
                        .link: urlString,
                        .foregroundColor: theme.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ], range: NSRange(location: 0, length: fallback.length))
                }
                attributed.replaceCharacters(in: fullRange, with: fallback)
            }
        }
    }
    
    private func resolveResourceURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        
        // First, try a standard URL (file:// / https:// / etc.)
        if let u = URL(string: trimmed), u.scheme != nil {
            return u
        }
        
        // File paths: support ~, absolute, and relative paths.
        let path: String
        if trimmed.hasPrefix("~") {
            path = NSString(string: trimmed).expandingTildeInPath
        } else if trimmed.hasPrefix("/") {
            path = trimmed
        } else if let baseURL {
            path = baseURL.appendingPathComponent(trimmed).path
        } else {
            path = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(trimmed)
        }
        
        return URL(fileURLWithPath: path)
    }
    
    private func applyInlinePattern(
        pattern: String,
        in attributed: NSMutableAttributedString,
        replaceWithCapture captureIndex: Int,
        skipIfInsideCode: Bool = false,
        apply: (NSRange) -> Void
    ) {
        applyInlinePattern(pattern: pattern, in: attributed, replaceWithCapture: captureIndex, skipIfInsideCode: skipIfInsideCode) { range, _ in
            apply(range)
        }
    }
    
    private func applyInlinePattern(
        pattern: String,
        in attributed: NSMutableAttributedString,
        replaceWithCapture captureIndex: Int,
        skipIfInsideCode: Bool = false,
        apply: (NSRange, [String]) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let s = attributed.string
        let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
        guard !matches.isEmpty else { return }
        
        for match in matches.reversed() {
            guard match.numberOfRanges > captureIndex else { continue }
            let fullRange = match.range(at: 0)
            let captureRange = match.range(at: captureIndex)
            if fullRange.location == NSNotFound || captureRange.location == NSNotFound { continue }
            
            if skipIfInsideCode && rangeIntersectsCode(attributed, range: fullRange) {
                continue
            }
            
            let captureText = (s as NSString).substring(with: captureRange)
            var captures: [String] = []
            for i in 0..<match.numberOfRanges {
                let r = match.range(at: i)
                if r.location == NSNotFound {
                    captures.append("")
                } else {
                    captures.append((s as NSString).substring(with: r))
                }
            }
            
            attributed.replaceCharacters(in: fullRange, with: captureText)
            let newRange = NSRange(location: fullRange.location, length: (captureText as NSString).length)
            apply(newRange, captures)
        }
    }
    
    private func rangeIntersectsCode(_ attributed: NSAttributedString, range: NSRange) -> Bool {
        var intersects = false
        attributed.enumerateAttribute(Self.isCodeAttribute, in: range, options: []) { value, _, stop in
            if value != nil {
                intersects = true
                stop.pointee = true
            }
        }
        return intersects
    }
}

// MARK: - Code Highlight (Highlightr)

private enum NativeHighlightr {
    // Highlightr init can fail (resources/JSContext), so keep it optional.
    private static let shared: Highlightr? = Highlightr()

    private static func isDarkMode() -> Bool {
        guard let app = NSApp else { return false }
        return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func highlight(code: String, languageHint: String, theme: NativeMarkdownTheme) -> NSAttributedString? {
        guard let hl = shared else { return nil }

        // Set code font (including bold/italic variants).
        hl.theme.setCodeFont(theme.monoFont)

        // Switch theme based on appearance (if setting fails, keep the default).
        let desired = isDarkMode() ? "paraiso-dark" : "paraiso-light"
        _ = hl.setTheme(to: desired)

        let lang = languageHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let langOrNil: String? = lang.isEmpty ? nil : lang
        return hl.highlight(code, as: langOrNil, fastRender: true)
    }
}

// MARK: - Code Highlight (regex-based)

private enum NativeCodeHighlighter {
    
    static func applyRegexHighlight(to attributed: NSMutableAttributedString, languageHint: String, theme: NativeMarkdownTheme) {
        let language = languageHint.lowercased()
        
        // Apply generic rules first (strings / numbers / comments).
        applyRegex(#""(?:\\.|[^"\\])*""#, to: attributed, color: NSColor.systemRed)
        applyRegex(#"'(?:\\.|[^'\\])*'"#, to: attributed, color: NSColor.systemRed)
        applyRegex(#"\b\d+(\.\d+)?\b"#, to: attributed, color: NSColor.systemOrange)
        
        // Single-line comments (Swift/JS) and Python comments
        applyRegex(#"//.*$"#, to: attributed, color: NSColor.systemGreen, options: [.anchorsMatchLines])
        applyRegex(#"#.*$"#, to: attributed, color: NSColor.systemGreen, options: [.anchorsMatchLines])
        
        // Apply language-specific keywords
        switch language {
        case "swift":
            applyKeywords([
                "import", "class", "struct", "enum", "protocol", "extension",
                "func", "let", "var", "if", "else", "switch", "case", "default",
                "for", "while", "do", "catch", "try", "throw", "throws", "rethrows",
                "return", "break", "continue", "guard", "defer",
                "public", "internal", "private", "fileprivate", "open",
                "static", "final", "override", "lazy", "weak", "unowned",
                "nil", "true", "false", "self", "super", "init"
            ], to: attributed, color: NSColor.systemPurple)
            
            // Types (very rough): identifiers starting with an uppercase letter
            applyRegex(#"\b[A-Z][A-Za-z0-9_]*\b"#, to: attributed, color: NSColor.systemBlue)
            
        case "python":
            applyKeywords([
                "def", "class", "import", "from", "as", "return",
                "if", "elif", "else", "for", "while", "break", "continue",
                "try", "except", "finally", "raise",
                "with", "lambda", "pass", "yield",
                "True", "False", "None"
            ], to: attributed, color: NSColor.systemPurple)
            
        case "javascript", "js", "typescript", "ts":
            applyKeywords([
                "const", "let", "var", "function", "return",
                "if", "else", "switch", "case", "default",
                "for", "while", "break", "continue",
                "try", "catch", "finally", "throw",
                "class", "extends", "new", "this", "super",
                "import", "from", "export", "async", "await",
                "true", "false", "null", "undefined"
            ], to: attributed, color: NSColor.systemPurple)
            
        default:
            // Unknown language: only generic rules
            break
        }
    }
    
    private static func applyKeywords(_ keywords: [String], to attributed: NSMutableAttributedString, color: NSColor) {
        guard !keywords.isEmpty else { return }
        let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        applyRegex(#"\b(\#(escaped))\b"#, to: attributed, color: color)
    }
    
    private static func applyRegex(_ pattern: String, to attributed: NSMutableAttributedString, color: NSColor, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let s = attributed.string
        let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
        for m in matches {
            attributed.addAttributes([.foregroundColor: color], range: m.range(at: 0))
        }
    }
}

