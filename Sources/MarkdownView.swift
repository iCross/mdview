// MarkdownView.swift
// macOS Markdown Viewer - WebKit 視圖元件

import AppKit
import Foundation
import WebKit

// MARK: - Shared Protocols (WebKit / Native)

protocol MarkdownDropDelegate: AnyObject {
    func markdownView(_ view: NSView, didReceiveDroppedFile path: String)
}

protocol MarkdownRenderable: AnyObject {
    var dropDelegate: MarkdownDropDelegate? { get set }
    /// 設定目前文件 URL（用於相對路徑解析，例如圖片/連結）。
    func setDocumentURL(_ url: URL?)
    func renderMarkdown(_ content: String)
    func loadWelcomePage()
    func zoomIn()
    func zoomOut()
    func resetZoom()
}

// MARK: - MarkdownView

class MarkdownView: NSView, MarkdownRenderable {
    
    // MARK: - Properties
    
    weak var dropDelegate: MarkdownDropDelegate?
    private var webView: WKWebView!
    private var htmlTemplate: String = ""
    private var documentURL: URL?
    private var currentZoomLevel: Double = 1.0
    private let zoomStep: Double = 0.1
    private let minZoom: Double = 0.5
    private let maxZoom: Double = 3.0
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupWebView()
        loadHTMLTemplate()
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWebView()
        loadHTMLTemplate()
        registerForDraggedTypes([.fileURL])
    }
    
    // MARK: - Setup
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        webView = WKWebView(frame: bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        
        // 允許本地檔案存取
        webView.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        addSubview(webView)
    }
    
    private func loadHTMLTemplate() {
        // 內嵌 HTML 模板，包含 marked.js 和 highlight.js
        htmlTemplate = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Markdown Viewer</title>
            <!-- highlight.js CDN -->
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" id="hljs-light">
            <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" id="hljs-dark" disabled>
            <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
            <!-- marked.js CDN -->
            <script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.0/marked.min.js"></script>
            <style>
                :root {
                    --bg-color: #ffffff;
                    --text-color: #24292e;
                    --link-color: #0366d6;
                    --code-bg: #f6f8fa;
                    --border-color: #e1e4e8;
                    --blockquote-color: #6a737d;
                }
                
                @media (prefers-color-scheme: dark) {
                    :root {
                        --bg-color: #0d1117;
                        --text-color: #c9d1d9;
                        --link-color: #58a6ff;
                        --code-bg: #161b22;
                        --border-color: #30363d;
                        --blockquote-color: #8b949e;
                    }
                    #hljs-light { disabled: true; }
                    #hljs-dark { disabled: false; }
                }
                
                * {
                    box-sizing: border-box;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    font-size: 16px;
                    line-height: 1.6;
                    color: var(--text-color);
                    background-color: var(--bg-color);
                    margin: 0;
                    padding: 0;
                }
                
                #content {
                    padding: 20px 45px;
                }
                
                /* 一般文章維持舒服閱讀寬度；table 例外走全寬 */
                #content > * {
                    max-width: 900px;
                    margin-left: auto;
                    margin-right: auto;
                }
                
                #content > .table-wrapper {
                    max-width: none;
                    width: 100%;
                }
                
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                
                h1 { font-size: 2em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
                h2 { font-size: 1.5em; border-bottom: 1px solid var(--border-color); padding-bottom: 0.3em; }
                h3 { font-size: 1.25em; }
                h4 { font-size: 1em; }
                h5 { font-size: 0.875em; }
                h6 { font-size: 0.85em; color: var(--blockquote-color); }
                
                a {
                    color: var(--link-color);
                    text-decoration: none;
                }
                
                a:hover {
                    text-decoration: underline;
                }
                
                p {
                    margin-top: 0;
                    margin-bottom: 16px;
                }
                
                code {
                    font-family: "SF Mono", Menlo, Monaco, Consolas, monospace;
                    font-size: 85%;
                    background-color: var(--code-bg);
                    padding: 0.2em 0.4em;
                    border-radius: 6px;
                }
                
                pre {
                    background-color: var(--code-bg);
                    border-radius: 6px;
                    padding: 16px;
                    overflow: auto;
                    font-size: 85%;
                    line-height: 1.45;
                }
                
                pre code {
                    background-color: transparent;
                    padding: 0;
                    border-radius: 0;
                }
                
                blockquote {
                    margin: 0 0 16px 0;
                    padding: 0 1em;
                    color: var(--blockquote-color);
                    border-left: 0.25em solid var(--border-color);
                }
                
                /* 避免引用區塊內的段落預設 margin 造成「中間空一大段」 */
                blockquote p {
                    margin: 0;
                }
                
                blockquote p + p {
                    margin-top: 0.5em;
                }
                
                ul, ol {
                    margin-top: 0;
                    margin-bottom: 16px;
                    padding-left: 2em;
                }
                
                li + li {
                    margin-top: 0.25em;
                }
                
                .table-wrapper {
                    overflow-x: auto;
                    -webkit-overflow-scrolling: touch;
                    margin-bottom: 16px;
                }
                
                .table-wrapper table {
                    border-collapse: collapse;
                    table-layout: auto;
                    /* 欄寬盡量依內容決定 */
                    width: max-content;
                    margin-bottom: 0;
                }
                
                .table-wrapper th, .table-wrapper td {
                    border: 1px solid var(--border-color);
                    padding: 6px 13px;
                    white-space: nowrap;
                }
                
                .table-wrapper th {
                    font-weight: 600;
                    background-color: var(--code-bg);
                }
                
                .table-wrapper tr:nth-child(2n) {
                    background-color: var(--code-bg);
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                }
                
                hr {
                    border: 0;
                    border-top: 1px solid var(--border-color);
                    margin: 24px 0;
                }
                
                .task-list-item {
                    list-style-type: none;
                }
                
                .task-list-item input {
                    margin-right: 0.5em;
                }
                
                /* 歡迎頁面樣式 */
                .welcome {
                    text-align: center;
                    padding: 60px 20px;
                }
                
                .welcome h1 {
                    border: none;
                    font-size: 2.5em;
                    margin-bottom: 20px;
                }
                
                .welcome p {
                    font-size: 1.1em;
                    color: var(--blockquote-color);
                }
                
                .welcome .hint {
                    margin-top: 40px;
                    padding: 20px;
                    background-color: var(--code-bg);
                    border-radius: 8px;
                }
                
                .welcome code {
                    font-size: 1em;
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                // 設定 marked.js
                marked.setOptions({
                    highlight: function(code, lang) {
                        if (lang && hljs.getLanguage(lang)) {
                            return hljs.highlight(code, { language: lang }).value;
                        }
                        return hljs.highlightAuto(code).value;
                    },
                    breaks: false,
                    gfm: true
                });
                
                // 深色模式切換
                function updateDarkMode() {
                    const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                    document.getElementById('hljs-light').disabled = isDark;
                    document.getElementById('hljs-dark').disabled = !isDark;
                }
                
                window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateDarkMode);
                updateDarkMode();
                
                // 渲染 Markdown
                function renderMarkdown(markdown) {
                    const contentEl = document.getElementById('content');
                    contentEl.innerHTML = marked.parse(markdown);
                    
                    // 將 table 包一層可水平捲動的 wrapper（避免超寬撐爆版面）
                    contentEl.querySelectorAll('table').forEach((table) => {
                        const parent = table.parentElement;
                        if (parent && parent.classList.contains('table-wrapper')) return;
                        const wrapper = document.createElement('div');
                        wrapper.className = 'table-wrapper';
                        if (table.parentNode) {
                            table.parentNode.insertBefore(wrapper, table);
                            wrapper.appendChild(table);
                        }
                    });
                    
                    // 重新套用語法高亮
                    document.querySelectorAll('pre code').forEach((block) => {
                        hljs.highlightElement(block);
                    });
                }
                
                // 顯示歡迎頁面
                function showWelcome() {
                    document.getElementById('content').innerHTML = `
                        <div class="welcome">
                            <h1>📝 Markdown Viewer</h1>
                            <p>一個簡潔的 macOS Markdown 檢視器</p>
                            <div class="hint">
                                <p><strong>開始使用：</strong></p>
                                <p>拖放 Markdown 檔案到此視窗</p>
                                <p>或使用 <code>File → Open</code> 開啟檔案</p>
                                <p>或使用命令列：<code>./mdviewer path/to/file.md</code></p>
                            </div>
                        </div>
                    `;
                }
            </script>
        </body>
        </html>
        """
    }
    
    // MARK: - Public Methods
    
    func setDocumentURL(_ url: URL?) {
        documentURL = url
    }
    
    func renderMarkdown(_ content: String) {
        // 轉義 JavaScript 字串中的特殊字元
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        let html = htmlTemplate
        // baseURL 設定成文件所在目錄，讓 Markdown 內的相對圖片/連結可解析
        let baseURL = documentURL?.deletingLastPathComponent()
        webView.loadHTMLString(html, baseURL: baseURL)
        
        // 等待頁面載入後執行 JavaScript
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            let js = "renderMarkdown(`\(escapedContent)`);"
            self?.webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("JavaScript 執行錯誤: \(error)")
                }
            }
        }
    }
    
    func loadWelcomePage() {
        webView.loadHTMLString(htmlTemplate, baseURL: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.webView.evaluateJavaScript("showWelcome();", completionHandler: nil)
        }
    }
    
    // MARK: - Zoom Methods
    
    func zoomIn() {
        currentZoomLevel = min(currentZoomLevel + zoomStep, maxZoom)
        applyZoom()
    }
    
    func zoomOut() {
        currentZoomLevel = max(currentZoomLevel - zoomStep, minZoom)
        applyZoom()
    }
    
    func resetZoom() {
        currentZoomLevel = 1.0
        applyZoom()
    }
    
    private func applyZoom() {
        if #available(macOS 11.0, *) {
            webView.pageZoom = currentZoomLevel
        } else {
            // macOS 10.15：WKWebView 尚無 pageZoom，改用 magnification
            let center = CGPoint(x: webView.bounds.midX, y: webView.bounds.midY)
            webView.setMagnification(currentZoomLevel, centeredAt: center)
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

    // MARK: - Snapshot (for automated GUI verification)

    /// 使用 `WKWebView.takeSnapshot` 取得穩定的渲染結果（比 cacheDisplay 更可靠）。
    /// 用於 `--screenshot` 這類「啟動 GUI → 截圖 → 自動退出」的測試模式。
    func captureSnapshotPNG(to url: URL, completion: @escaping (Bool) -> Void) {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            completion(false)
            return
        }

        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds

        webView.takeSnapshot(with: config) { image, error in
            if let error = error {
                print("Snapshot 失敗: \(error)")
            }
            guard let image else {
                completion(false)
                return
            }
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else {
                completion(false)
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
}
