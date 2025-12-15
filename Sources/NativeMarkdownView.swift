// NativeMarkdownView.swift
// macOS Markdown Viewer - 原生 NSTextView 渲染元件

import AppKit
import Foundation
import Markdown
import Highlightr

enum NativeMarkdownPipeline: String {
    case regex = "regex"
    case ast = "ast"
}

/// 使用 NSTextView 以 NSAttributedString 呈現 Markdown。
/// 設計目標：較低常駐成本、快速啟動、無 HTML/JS 渲染依賴。
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
            // Notes 風格：避免 TextKit 預設 padding 影響左右邊界（我們用 textContainerInset 控制）
            container.lineFragmentPadding = 0
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
        // 以 scrollView 可視內容寬度為準，避免 code block/table 變成「一個字寬」。
        // 注意：用 contentSize 比 bounds 更貼近實際可用寬度（會排除 scroller 佔用等）。
        let visibleWidth = scrollView.contentSize.width
        let insetWidth = textView.textContainerInset.width
        let containerWidth = max(1, visibleWidth - insetWidth * 2)
        guard containerWidth > 1 else { return }
        
        // 讓 textView 本身也有合理寬度
        var frame = textView.frame
        if abs(frame.width - visibleWidth) > 0.5 {
            frame.size.width = visibleWidth
            textView.frame = frame
        }
        
        if let container = textView.textContainer {
            container.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            container.widthTracksTextView = true
            
            // 強制讓 layout manager 重新依新幾何排版（修正「變寬了但還是每字換行」的殘留狀態）
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
        
        // 將結果塞入 textStorage
        textView.textStorage?.setAttributedString(attributed)

        // 確保第一次渲染就以正確容器寬度 reflow（table/code block 常在這裡回歸）
        syncTextContainerWidth()
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        
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
    
    /// 不啟動 GUI 的情況下輸出可測試的解析結果（供 `--dump` 使用）。
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
    
    /// 不啟動 GUI 的情況下輸出渲染後的純文字（用於驗證 fenced code block 後續內容不會被吃掉）。
    static func debugRenderPlainText(markdown: String, pipeline: NativeMarkdownPipeline = .regex) -> String {
        let theme = NativeMarkdownTheme(zoom: 1.0)
        let attributed: NSAttributedString
        if pipeline == .ast, ASTMarkdownRenderer.canRender(markdown: markdown) {
            attributed = ASTMarkdownRenderer(theme: theme).render(markdown: markdown)
        } else {
            attributed = NativeMarkdownParser(theme: theme, baseURL: nil, maxTableWidth: nil).render(markdown: markdown)
        }
        // 渲染器內部可能使用 U+2028（line separator）避免段落間距問題；
        // debug/測試輸出時統一轉回 "\n" 以便做字串比對與在 terminal 觀察。
        return attributed.string.replacingOccurrences(of: "\u{2028}", with: "\n")
    }

    /// 不啟動 GUI 的情況下驗證 NSTextView/NSScrollView 寬度骨架是否正常（供 `--skeleton-check` 使用）。
    /// 目標：避免回歸成「每字換行」（通常是 text container 寬度被錯誤同步成極小值）。
    static func debugSkeletonCheck() -> String {
        // 保守起見先初始化 NSApplication（即使不進 event loop）
        _ = NSApplication.shared

        let view = NativeMarkdownView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        view.loadWelcomePage()

        // 模擬縮放視窗寬度（常見觸發點：scrollbar/clipView bounds 變化）
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

            // 容忍少量誤差（浮點/布局時序）
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

    /// 捲到第一個包含指定文字的位置（供 `--screenshot-scroll-to` 使用）。
    /// - Returns: 是否找到並捲動成功
    func scrollToFirstOccurrence(of text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }

        let haystack = textView.string
        guard let r = haystack.range(of: needle) else { return false }
        let nsRange = NSRange(r, in: haystack)
        textView.scrollRangeToVisible(nsRange)
        return true
    }

    /// 捲到指定 y offset（點數；以「文件頂端」為 0）。
    func scrollTo(y: CGFloat) {
        let doc = scrollView.documentView ?? textView
        let viewportHeight = scrollView.contentSize.height
        let maxOffset = max(0, doc.bounds.height - viewportHeight)
        let requested = max(0, y)

        let targetY: CGFloat
        if doc.isFlipped {
            targetY = min(requested, maxOffset)
        } else {
            // 若座標系非 flipped，將「從頂端起算」轉成「從底端起算」
            targetY = min(max(0, maxOffset - requested), maxOffset)
        }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// 取得「整份文件內容」用於 full-page screenshot 的 view（documentView）。
    /// 目前回傳 NSTextView 本身（其 frame 高度會隨內容成長）。
    func viewForFullScreenshot() -> NSView {
        // 先確保 layout 完整，並把 textView 的高度拉到足夠容納內容（避免只截到首屏）。
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
    
    /// inline code 用：跟隨當下文字大小（避免在標題/大字時 inline code 看起來特別小）
    func monoFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    // Notes 風格 paragraph style（Reader 為主：一致行高、段落間距）
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
        // 標題：讓上下更有呼吸感
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
    /// Native table 的最大寬度（點數）。若 nil，使用保守預設值。
    /// - 目的：小表格可依內容寬度顯示；遇到超寬內容時避免變成超大 table（改以換行/自動佈局處理）。
    private let maxTableWidth: CGFloat?
    
    // 自訂屬性：用來避免在 code span 內再套用粗體/斜體等規則
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
            // 段落間距由 paragraphStyle 的 paragraphSpacing 控制，這裡只加單一換行
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
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // 標題（# ~ ######）
            if let heading = parseHeading(line) {
                flushPendingParagraph()
                output.append(renderHeading(level: heading.level, text: heading.text))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // 引用（>）：以 block-level 解析連續 quote 行，避免「一行一個 block」導致 paragraphSpacing 疊加
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

            // 表格（GitHub-style pipe table）
            if i + 1 < lines.count, looksLikeTableHeader(lines[i], separatorLine: lines[i + 1]) {
                flushPendingParagraph()
                let (table, consumed) = parseTable(from: lines, startIndex: i)
                output.append(renderTable(table))
                output.append(NSAttributedString(string: "\n"))
                i += consumed
                continue
            }
            
            // 待辦清單 / 無序清單
            if let task = parseTaskListItem(line) {
                flushPendingParagraph()
                output.append(renderListItem(prefix: task.checked ? "☑︎" : "☐", text: task.text))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            if let bullet = parseBulletListItem(line) {
                flushPendingParagraph()
                output.append(renderListItem(prefix: "•", text: bullet))
                output.append(NSAttributedString(string: "\n"))
                i += 1
                continue
            }
            
            // 有序清單（1.）
            if let ordered = parseOrderedListItem(line) {
                flushPendingParagraph()
                // ordered list：用 "." + tab 做對齊（類似 Notes）
                output.append(renderListItem(prefix: "\(ordered.index).", text: ordered.text))
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
            let content = String(rest) // 可能是空字串（對應 `>` 空行）
            quoteLines.append(content)
            i += 1
        }

        // 正規化：同一段落內用 U+2028（line separator）串接，避免被當成新 paragraph；
        // `>` 空行代表段落分隔，段落間用 \n\n。
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
            .foregroundColor: theme.textColor,
            .paragraphStyle: theme.headingParagraphStyle(level: level)
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
        paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
        paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = 10
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.paragraphFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let out = NSMutableAttributedString(attributedString: formatInline(text, baseAttributes: attrs))
        // 確保全文（含 \n）都套用 blockquote paragraphStyle
        if out.length > 0 {
            out.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: out.length))
        }
        return out
    }
    
    private func renderListItem(prefix: String, text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        // Notes.app 風格：用 tab stop 做出「符號/數字在左、文字統一對齊」的 hanging indent。
        // - prefix 後用 \t
        // - text 從 tab stop 開始
        let bulletIndent: CGFloat = 14
        let prefixWidth = (prefix as NSString).size(withAttributes: [.font: theme.paragraphFont]).width
        let minTextIndent: CGFloat = 32
        let textIndent = max(minTextIndent, bulletIndent + prefixWidth + 12)
        
        // 第一行（符號/數字）先縮排到 bulletIndent；文字用 tab 跳到 textIndent。
        paragraphStyle.firstLineHeadIndent = bulletIndent
        // 換行後的內容對齊文字起始（hanging indent）
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
        
        // prefix 不要帶尾端空白，改由 \t 讓文字對齊 tab stop
        let out = NSMutableAttributedString(string: "\(prefix)\t", attributes: base)
        out.append(formatInline(text, baseAttributes: base))
        return out
    }
    
    private func renderHorizontalRule() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
        paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = 10
        
        return NSAttributedString(string: "──────────", attributes: [
            .font: theme.paragraphFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: paragraphStyle
        ])
    }
    
    private func renderCodeBlock(_ code: String, language: String) -> NSAttributedString {
        let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

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
        paragraphStyle.lineHeightMultiple = theme.baseParagraphStyle.lineHeightMultiple
        paragraphStyle.lineSpacing = theme.baseParagraphStyle.lineSpacing
        paragraphStyle.paragraphSpacing = 10
        
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.monoFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle
        ]

        // Mermaid：若啟用且 `mmdc` 可用，嘗試渲染成圖片；失敗則 fallback 顯示 source。
        if lang == "mermaid" {
            let maxW = maxTableWidth
            if let attachment = MermaidRenderer.renderAttachmentIfPossible(code: code, theme: theme, maxWidth: maxW) {
                let out = NSMutableAttributedString(attributedString: attachment)
                out.append(NSAttributedString(string: "\n", attributes: baseAttrs))
                out.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: out.length))
                return out
            }
        }

        // 優先使用 Highlightr（highlight.js via JavaScriptCore）；失敗再 fallback 到 regex。
        let out: NSMutableAttributedString
        if let highlighted = NativeHighlightr.highlight(code: code, languageHint: language, theme: theme) {
            out = NSMutableAttributedString(attributedString: highlighted)
            out.append(NSAttributedString(string: "\n", attributes: baseAttrs))
        } else {
            out = NSMutableAttributedString(string: code + "\n", attributes: baseAttrs)
            NativeCodeHighlighter.applyRegexHighlight(to: out, languageHint: language, theme: theme)
        }
        
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
        // content-driven：小表格不強制撐滿視窗，避免每欄大片空白
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let out = NSMutableAttributedString()

        // 估算欄寬：用字型量測出「內容導向」的 table 寬度（小表格會比較緊湊）
        func measure(_ s: String, font: NSFont) -> CGFloat {
            let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return 0 }
            return (text as NSString).size(withAttributes: [.font: font]).width
        }

        // cell 的 padding / border（需與下方 block 設定一致）
        let cellPadding: CGFloat = 6
        let cellBorder: CGFloat = 1
        let cellExtra: CGFloat = cellPadding * 2 + cellBorder * 2 + 8  // 多留一點避免緊貼

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
            // 小表格：整張 table 依內容寬度
            textTable.setContentWidth(intrinsicWidth, type: .absoluteValueType)
        } else {
            // 超寬表格：限制最大寬，讓 TextKit 以自動佈局 + 換行處理
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
                // 小表格：每欄使用內容估算的固定寬度
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
            let baseFont = (baseAttributes[.font] as? NSFont) ?? theme.paragraphFont
            attributed.addAttributes([
                .font: theme.monoFont(ofSize: baseFont.pointSize),
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

// MARK: - Code Highlight (Highlightr)

private enum NativeHighlightr {
    // Highlightr init 可能失敗（資源/JSContext），因此用 optional
    private static let shared: Highlightr? = Highlightr()

    private static func isDarkMode() -> Bool {
        guard let app = NSApp else { return false }
        return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static func highlight(code: String, languageHint: String, theme: NativeMarkdownTheme) -> NSAttributedString? {
        guard let hl = shared else { return nil }

        // 設定字型（含 bold/italic 變體）
        hl.theme.setCodeFont(theme.monoFont)

        // 依外觀切 theme（若指定失敗就沿用預設 pojoaque）
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

