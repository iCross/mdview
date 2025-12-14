// NativeMarkdownView.swift
// macOS Markdown Viewer - 原生 NSTextView 渲染元件（不使用 WKWebView）

import AppKit
import Foundation

/// 使用 NSTextView 以 NSAttributedString 呈現 Markdown。
/// 設計目標：較低常駐成本、快速啟動、無 WebKit/JS 依賴。
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
    
    private var clipViewBoundsObserver: NSObjectProtocol?
    private var clipViewFrameObserver: NSObjectProtocol?
    
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
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        
        scrollView.documentView = textView
        addSubview(scrollView)

        // 讓內容寬度跟著 view（原生閱讀器的自然換行）
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.heightTracksTextView = false
            container.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        }
        
        // 關鍵：documentView（NSTextView）需要有初始尺寸，否則可能變成極小寬度導致每字換行
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setFrameSize(scrollView.contentView.bounds.size)
        
        startObservingScrollViewGeometry()
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
    
    private func syncTextContainerWidth() {
        // 以 scrollView 可視內容寬度為準，避免 code block/table 變成「一個字寬」
        let visibleWidth = scrollView.contentView.bounds.width
        guard visibleWidth > 1 else { return }
        
        // 讓 textView 本身也有合理寬度
        var frame = textView.frame
        if abs(frame.width - visibleWidth) > 0.5 {
            frame.size.width = visibleWidth
            textView.frame = frame
        }
        
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: visibleWidth, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            
            // 強制讓 layout manager 重新依新幾何排版（修正「變寬了但還是每字換行」的殘留狀態）
            textView.layoutManager?.textContainerChangedGeometry(container)
        }
    }
    
    // MARK: - MarkdownRenderable

    func setDocumentURL(_ url: URL?) {
        documentURL = url
    }
    
    func renderMarkdown(_ content: String) {
        lastMarkdownSource = content
        isShowingWelcome = false
        
        let theme = NativeMarkdownTheme(zoom: currentZoomLevel)
        let baseURL = documentURL?.deletingLastPathComponent()
        let attributed = NativeMarkdownParser(theme: theme, baseURL: baseURL).render(markdown: content)
        
        // 將結果塞入 textStorage
        textView.textStorage?.setAttributedString(attributed)
        
        // 將游標回到頂端
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    
    func loadWelcomePage() {
        lastMarkdownSource = nil
        isShowingWelcome = true
        
        let theme = NativeMarkdownTheme(zoom: currentZoomLevel)
        let welcome = """
        # Markdown Viewer
        
        一個簡潔的 macOS Markdown 檢視器（原生渲染模式）。
        
        ## 開始使用
        
        - 拖放 `.md` / `.markdown` 檔案到此視窗
        - 或使用選單 `File → Open` 開啟檔案
        - 或使用命令列：`./mdviewer path/to/file.md`
        """
        
        let attributed = NativeMarkdownParser(theme: theme, baseURL: nil).render(markdown: welcome)
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
    
    /// 不啟動 GUI 的情況下輸出可測試的解析結果（供 `--native-dump` 使用）。
    static func debugDump(markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        var out: [String] = []
        let imageRegex = try? NSRegularExpression(pattern: "!\\[([^\\]]*?)\\]\\(([^\\)]+?)\\)", options: [])
        var i = 0
        while i < lines.count {
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
                let line = lines[i]
                let matches = imageRegex.matches(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length))
                for m in matches {
                    guard m.numberOfRanges >= 3 else { continue }
                    let alt = (line as NSString).substring(with: m.range(at: 1))
                    let url = (line as NSString).substring(with: m.range(at: 2))
                    out.append("[[IMAGE]] \(alt) | \(url)")
                }
            }
            out.append(lines[i])
            i += 1
        }
        
        return out.joined(separator: "\n")
    }
    
    /// 不啟動 GUI 的情況下輸出 Native 解析後的純文字（用於驗證 fenced code block 後續內容不會被吃掉）。
    static func debugRenderPlainText(markdown: String) -> String {
        let theme = NativeMarkdownTheme(zoom: 1.0)
        let attributed = NativeMarkdownParser(theme: theme, baseURL: nil).render(markdown: markdown)
        return attributed.string
    }
}

// MARK: - Theme

private struct NativeMarkdownTheme {
    let zoom: Double
    
    // 基本文字尺寸（會乘上 zoom）
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
    
    // 動態色彩（自動跟隨深色/淺色）
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

/// 極簡 Markdown 轉 NSAttributedString：
/// - 支援：標題、段落、引用、列表、待辦、水平線、inline code、粗體/斜體/刪除線、連結、fenced code block（含簡易 regex 上色）
private final class NativeMarkdownParser {
    
    private let theme: NativeMarkdownTheme
    private let baseURL: URL?
    
    // 自訂屬性：用來避免在 code span 內再套用粗體/斜體等規則
    private static let isCodeAttribute = NSAttributedString.Key("NativeMarkdownIsCode")
    
    init(theme: NativeMarkdownTheme, baseURL: URL?) {
        self.theme = theme
        self.baseURL = baseURL
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
                .foregroundColor: theme.textColor
            ]
            output.append(formatInline(text, baseAttributes: attrs))
            output.append(NSAttributedString(string: "\n\n"))
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
                    output.append(NSAttributedString(string: "\n\n"))
                    inCodeFence = false
                    codeFenceLanguage = ""
                    codeBuffer.removeAll(keepingCapacity: true)
                    // 重要：吃掉這一行 closing fence，否則會被下一輪當成 opening fence
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
            
            // 空行：結束段落
            if trimmed.isEmpty {
                flushPendingParagraph()
                i += 1
                continue
            }
            
            // 水平線
            if trimmed == "---" || trimmed == "----" || trimmed == "-----" {
                flushPendingParagraph()
                output.append(renderHorizontalRule())
                output.append(NSAttributedString(string: "\n\n"))
                i += 1
                continue
            }
            
            // 標題（# ~ ######）
            if let heading = parseHeading(line) {
                flushPendingParagraph()
                output.append(renderHeading(level: heading.level, text: heading.text))
                output.append(NSAttributedString(string: "\n\n"))
                i += 1
                continue
            }
            
            // 引用（>）
            if let quoteText = parseBlockquote(line) {
                flushPendingParagraph()
                output.append(renderBlockquote(quoteText))
                output.append(NSAttributedString(string: "\n\n"))
                i += 1
                continue
            }

            // 表格（GitHub-style pipe table）
            if i + 1 < lines.count, looksLikeTableHeader(lines[i], separatorLine: lines[i + 1]) {
                flushPendingParagraph()
                let (table, consumed) = parseTable(from: lines, startIndex: i)
                output.append(renderTable(table))
                output.append(NSAttributedString(string: "\n\n"))
                i += consumed
                continue
            }
            
            // 待辦清單 / 無序清單
            if let task = parseTaskListItem(line) {
                flushPendingParagraph()
                output.append(renderListItem(prefix: task.checked ? "☑︎ " : "☐ ", text: task.text))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            if let bullet = parseBulletListItem(line) {
                flushPendingParagraph()
                output.append(renderListItem(prefix: "• ", text: bullet))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // 有序清單（1.）
            if let ordered = parseOrderedListItem(line) {
                flushPendingParagraph()
                output.append(renderListItem(prefix: "\(ordered.index). ", text: ordered.text))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // 其他：累積成段落
            pendingParagraphLines.append(line)
            i += 1
        }
        
        // flush remaining
        flushPendingParagraph()
        
        // 若文件以列表結尾，避免多餘的尾端空白：保留即可（textView 可接受）
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
    
    private func parseBlockquote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        let rest = trimmed.dropFirst()
        return String(rest).trimmingCharacters(in: .whitespaces)
    }
    
    private func parseTaskListItem(_ line: String) -> (checked: Bool, text: String)? {
        // "- [x] text" / "- [ ] text"
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
        return (checked, text)
    }
    
    private func parseBulletListItem(_ line: String) -> String? {
        // "- text" "* text" "+ text"
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") else { return nil }
        return String(trimmed.dropFirst(2))
    }
    
    private func parseOrderedListItem(_ line: String) -> (index: Int, text: String)? {
        // "1. text"
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let numberPart = trimmed[..<dotIndex]
        guard let n = Int(numberPart), n >= 1 else { return nil }
        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.first == " " else { return nil }
        let text = afterDot.trimmingCharacters(in: .whitespaces)
        return (n, text)
    }
    
    // MARK: - Block Renderers
    
    private func renderHeading(level: Int, text: String) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.headingFont(level: level),
            .foregroundColor: theme.textColor
        ]
        return formatInline(text, baseAttributes: attrs)
    }
    
    private func renderBlockquote(_ text: String) -> NSAttributedString {
        // 用 NSTextBlock 做出原生的「引用區塊」視覺（左邊框 + padding）
        let block = NSTextBlock()
        block.backgroundColor = NSColor.clear
        // 重要：讓 block 吃滿可用寬度（否則預設可能導致寬度極小）
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(theme.codeBorderColor, for: .minX)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.textBlocks = [block]
        paragraphStyle.paragraphSpacing = 6
        paragraphStyle.lineSpacing = 2
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.paragraphFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let out = NSMutableAttributedString(attributedString: formatInline(text, baseAttributes: attrs))
        out.append(NSAttributedString(string: "\n", attributes: attrs))
        out.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: out.length))
        return out
    }
    
    private func renderListItem(prefix: String, text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 22
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.paragraphSpacing = 2
        
        let base: [NSAttributedString.Key: Any] = [
            .font: theme.paragraphFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let out = NSMutableAttributedString(string: prefix, attributes: base)
        out.append(formatInline(text, baseAttributes: base))
        return out
    }
    
    private func renderHorizontalRule() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacing = 6
        
        return NSAttributedString(string: "──────────", attributes: [
            .font: theme.paragraphFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle
        ])
    }
    
    private func renderCodeBlock(_ code: String, language: String) -> NSAttributedString {
        // 用 NSTextBlock 做出原生的 code block（背景 + padding + 邊框）
        let block = NSTextBlock()
        block.backgroundColor = theme.codeBackgroundColor
        // 重要：讓 block 吃滿可用寬度（避免每字換行的「一個字寬」code block）
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(theme.codeBorderColor)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.textBlocks = [block]
        paragraphStyle.paragraphSpacing = 10
        paragraphStyle.lineSpacing = 2
        
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let out = NSMutableAttributedString(string: code + "\n", attributes: baseAttrs)
        
        // 套用簡易語法高亮（regex）
        NativeCodeHighlighter.applyHighlight(to: out, languageHint: language, theme: theme)
        
        // 標示成 code（避免後續 inline 規則覆蓋）
        out.addAttribute(Self.isCodeAttribute, value: true, range: NSRange(location: 0, length: out.length))
        out.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: out.length))
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
            // 若遇到明顯是其他語法（例如 list），就停
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
        // 支援兩種：
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
        // 使用 NSTextTable/NSTextTableBlock 產生真正的 table 版面（NSTextView 會做 cell layout）
        let allRows = [table.header] + table.rows
        let colCount = allRows.map(\.count).max() ?? 0
        guard colCount > 0 else { return NSAttributedString(string: "") }

        let textTable = NSTextTable()
        textTable.numberOfColumns = colCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false
        textTable.setContentWidth(100, type: .percentageValueType)

        let out = NSMutableAttributedString()

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

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.textBlocks = [block]
            paragraphStyle.paragraphSpacing = 0
            paragraphStyle.paragraphSpacingBefore = 0
            paragraphStyle.lineSpacing = 1.5

            let base: [NSAttributedString.Key: Any] = [
                .font: isHeader ? theme.boldFont : theme.paragraphFont,
                .foregroundColor: theme.textColor,
                .paragraphStyle: paragraphStyle
            ]

            // 允許 cell 內使用簡單 inline 格式（粗體/連結/inline code 等）
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

        // 表格後加些間距（外層也會加 \n\n，但避免 table block 黏在下一段）
        out.append(NSAttributedString(string: "\n"))
        return out
    }
    
    // MARK: - Inline Formatting
    
    private func formatInline(_ text: String, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: baseAttributes)
        
        // images：![alt](url)
        applyInlineImages(in: attributed, baseAttributes: baseAttributes)
        
        // code span：`code`
        applyInlinePattern(
            pattern: "`([^`]+)`",
            in: attributed,
            replaceWithCapture: 1
        ) { range in
            attributed.addAttributes([
                .font: theme.monoFont,
                .backgroundColor: theme.codeBackgroundColor,
                .foregroundColor: theme.textColor,
                Self.isCodeAttribute: true
            ], range: range)
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
        
        // bold：**text** / __text__
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
        
        // italic：*text* / _text_
        // 這裡採用保守規則，避免把列表符號等誤判成 italic：要求內文至少 2 字元。
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
            
            if let url = resolveResourceURL(urlString),
               let image = NSImage(contentsOf: url) {
                let attachment = NSTextAttachment()
                attachment.image = image
                
                // 以一個合理的最大寬度縮放，避免超大圖片撐爆版面
                let maxWidth: CGFloat = CGFloat(720.0 * theme.zoom)
                let size = image.size
                if size.width > 0 && size.height > 0 {
                    let ratio = min(1.0, maxWidth / size.width)
                    let displaySize = NSSize(width: size.width * ratio, height: size.height * ratio)
                    attachment.bounds = NSRect(x: 0, y: 0, width: displaySize.width, height: displaySize.height)
                }
                
                let imgString = NSAttributedString(attachment: attachment)
                attributed.replaceCharacters(in: fullRange, with: imgString)
            } else {
                // fallback：顯示 alt 或 Image 文字，並在可能時附上連結
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
        
        // 先嘗試標準 URL（含 file:// / https://）
        if let u = URL(string: trimmed), u.scheme != nil {
            return u
        }
        
        // 檔案路徑：支援 ~、絕對、相對
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

// MARK: - Code Highlight (regex-based)

private enum NativeCodeHighlighter {
    
    static func applyHighlight(to attributed: NSMutableAttributedString, languageHint: String, theme: NativeMarkdownTheme) {
        let language = languageHint.lowercased()
        
        // 先套用通用規則（strings / numbers / comments）
        applyRegex(#""(?:\\.|[^"\\])*""#, to: attributed, color: NSColor.systemRed)
        applyRegex(#"'(?:\\.|[^'\\])*'"#, to: attributed, color: NSColor.systemRed)
        applyRegex(#"\b\d+(\.\d+)?\b"#, to: attributed, color: NSColor.systemOrange)
        
        // 單行註解（Swift/JS）與 Python 註解
        applyRegex(#"//.*$"#, to: attributed, color: NSColor.systemGreen, options: [.anchorsMatchLines])
        applyRegex(#"#.*$"#, to: attributed, color: NSColor.systemGreen, options: [.anchorsMatchLines])
        
        // 依語言套 keyword
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
            
            // 型別（非常粗略）：以大寫開頭的識別字
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
            // 未知語言：只做通用規則
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

