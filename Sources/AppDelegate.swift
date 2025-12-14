// AppDelegate.swift
// macOS Markdown Viewer - 應用程式代理
import AppKit
import Foundation
import Darwin

private enum RendererMode: String {
    case webKit = "webkit"
    case native = "native"
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    var window: NSWindow!
    var markdownView: MarkdownView!
    var nativeMarkdownView: NativeMarkdownView!
    var rendererView: (NSView & MarkdownRenderable)?
    private var rendererMode: RendererMode = .webKit
    var menuBuilder: MenuBuilder!
    var fileHandler: FileHandler = FileHandler()  // 立即初始化
    var currentFilePath: String?
    var pendingFilePath: String?  // 儲存啟動前收到的檔案路徑
    
    private var isSmokeTestMode: Bool {
        CommandLine.arguments.contains("--smoke-test")
    }

    private var isAutomationMode: Bool {
        // 用於 CI/LLM：避免做會卡住的前景啟動行為（例如 activate）
        isSmokeTestMode || (screenshotOutputPath != nil)
    }

    private var screenshotOutputPath: String? {
        // 支援：
        // - --screenshot /path/to/out.png
        // - --screenshot=/path/to/out.png
        let args = CommandLine.arguments
        if let arg = args.first(where: { $0.hasPrefix("--screenshot=") }) {
            let path = arg.replacingOccurrences(of: "--screenshot=", with: "")
            return path.isEmpty ? nil : path
        }
        if let idx = args.firstIndex(of: "--screenshot") {
            let next = idx + 1
            guard next < args.count else { return nil }
            let path = args[next]
            return path.hasPrefix("-") ? nil : path
        }
        return nil
    }

    private var screenshotDelaySeconds: TimeInterval {
        // 支援：--screenshot-delay=1.2 或 --screenshot-delay 1.2
        let args = CommandLine.arguments
        if let arg = args.first(where: { $0.hasPrefix("--screenshot-delay=") }) {
            let v = arg.replacingOccurrences(of: "--screenshot-delay=", with: "")
            return TimeInterval(v) ?? 1.0
        }
        if let idx = args.firstIndex(of: "--screenshot-delay") {
            let next = idx + 1
            guard next < args.count else { return 1.0 }
            return TimeInterval(args[next]) ?? 1.0
        }
        return 1.0
    }
    
    private var didBootstrap: Bool = false
    
    private var preferredRendererMode: RendererMode {
        // 支援：
        // - --native / --webkit
        // - --renderer=native / --renderer=webkit
        let args = CommandLine.arguments
        if args.contains("--native") { return .native }
        if args.contains("--webkit") { return .webKit }
        
        if let rendererArg = args.first(where: { $0.hasPrefix("--renderer=") }) {
            let value = rendererArg.replacingOccurrences(of: "--renderer=", with: "").lowercased()
            return RendererMode(rawValue: value) ?? .webKit
        }
        return .webKit
    }

    private var preferredNativePipeline: NativeMarkdownPipeline {
        // 支援：
        // - --native-pipeline=regex|ast
        // - --native-ast（等同 ast）
        let args = CommandLine.arguments
        if args.contains("--native-ast") { return .ast }
        if let pipelineArg = args.first(where: { $0.hasPrefix("--native-pipeline=") }) {
            let value = pipelineArg.replacingOccurrences(of: "--native-pipeline=", with: "").lowercased()
            return NativeMarkdownPipeline(rawValue: value) ?? .regex
        }
        return .regex
    }
    
    // MARK: - NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrapIfNeeded()
    }
    
    /// 給「非 .app bundle、從 CLI 直接執行」的啟動路徑使用：
    /// 在某些情況下 AppKit 的 Launch 回呼時序不穩定，會導致視窗不出現。
    /// 這裡把啟動流程做成可重入且可手動觸發，確保一次到位顯示 GUI。
    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        
        // 再保險一次：確保是一般 GUI app（非 bundle 從 Terminal 啟動時特別重要）
        NSApp.setActivationPolicy(.regular)

        // 先確保「視窗一定會出現」：先建窗、先顯示，再初始化 WebKit（避免 WebKit 初始化卡住時整個 GUI 都不見）
        setupWindow()
        showWindowNow(activate: !isAutomationMode)

        // CLI smoke test：不初始化 WebKit，單純驗證「能顯示 GUI + 正常退出」
        if isSmokeTestMode {
            // 這裡不要依賴 timer（在某些自動化/無前景情境 timer 可能不觸發，會導致測試卡住）
            let ok = (window != nil) && window.isVisible && (NSApp.activationPolicy() == .regular)
            print(ok ? "SMOKE_OK" : "SMOKE_FAIL")
            fflush(stdout)
            Darwin.exit(ok ? 0 : 1)
        }

        // 其餘初始化放到下一個 tick，讓 AppKit event loop 穩定後再碰 WebKit
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupMarkdownView()
            self.setupMenu()
            self.setupFileHandler()
            self.processCommandLineArguments()

            // GUI 截圖模式：渲染後自動輸出 PNG 並退出（供測試/agent 使用）
            if let outPath = self.screenshotOutputPath {
                self.scheduleScreenshotAndExit(outputPath: outPath, delaySeconds: self.screenshotDelaySeconds)
            }
        }
    }
    
    private func showWindowNow(activate: Bool) {
        // 若 contentView 尚未建立，補一個避免後續 force unwrap
        if window.contentView == nil {
            let layoutSize = window.contentLayoutRect.size
            let fallbackSize = window.contentRect(forFrameRect: window.frame).size
            let size = (layoutSize.width > 0 && layoutSize.height > 0) ? layoutSize : fallbackSize
            window.contentView = NSView(frame: NSRect(origin: .zero, size: size))
        }
        
        // 放一個簡單的 placeholder，確保視窗一出來就有內容
        if let contentView = window.contentView, contentView.subviews.isEmpty {
            let label = NSTextField(labelWithString: "Loading…")
            label.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
        
        window.makeKeyAndOrderFront(nil)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // 如果視窗尚未準備好，先儲存路徑
        if window == nil || rendererView == nil {
            pendingFilePath = filename
        } else {
            loadMarkdownFile(path: filename)
        }
        return true
    }
    
    // MARK: - Setup Methods
    
    private func setupWindow() {
        // 以螢幕可用區域（排除 Dock/Menu bar）計算「舒服的」初始 content size，
        // 並加入上下限，避免太大或太小。
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let targetWidth: CGFloat = min(visibleFrame.width, min(1200, max(900, visibleFrame.width * 0.8)))
        // 高度偏向更「高」一些：預設用可用螢幕高度的 95%，但永遠不超過 visibleFrame
        //（避免每台螢幕不同時出現超出可用範圍）
        let targetHeight: CGFloat = min(visibleFrame.height, max(700, visibleFrame.height * 0.95))
        
        // 注意：contentRect 是「內容區」大小；之後用 center() 置中，避免踩到 title bar/frame 差異。
        let windowRect = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Markdown Viewer"
        // 避免視窗被縮到過小（閱讀下限）；小螢幕則依 visibleFrame 動態縮放。
        let minWidth = min(700, visibleFrame.width * 0.6)
        let minHeight = min(500, visibleFrame.height * 0.6)
        window.minSize = NSSize(width: max(400, minWidth), height: max(300, minHeight))
        window.isReleasedWhenClosed = false

        // 讓 macOS 記住使用者上次調整的視窗大小/位置（若有記錄，會自動恢復）
        window.setFrameAutosaveName("MainWindow")
        // 若曾 autosave 過，優先用上次的 frame；否則使用本次計算出的初始大小並置中
        let didRestoreFrame = window.setFrameUsingName("MainWindow")
        if didRestoreFrame {
            // 避免跨螢幕/解析度切換後，restore 的 frame 超出當前螢幕可用範圍
            let constrained = window.constrainFrameRect(window.frame, to: NSScreen.main)
            window.setFrame(constrained, display: false)
        } else {
            window.center()
        }
        
        // 設定視窗代理以支援拖放
        window.registerForDraggedTypes([.fileURL])
    }
    
    private func setupMarkdownView() {
        rendererMode = preferredRendererMode
        setRenderer(rendererMode)
    }
    
    private func setRenderer(_ mode: RendererMode) {
        rendererMode = mode
        
        guard let contentView = window.contentView else { return }
        
        // 清掉 placeholder / 舊 renderer
        contentView.subviews.forEach { $0.removeFromSuperview() }
        
        let view: (NSView & MarkdownRenderable)
        switch mode {
        case .webKit:
            if markdownView == nil {
                markdownView = MarkdownView(frame: contentView.bounds)
                markdownView.autoresizingMask = [.width, .height]
            } else {
                markdownView.frame = contentView.bounds
            }
            view = markdownView
        case .native:
            if nativeMarkdownView == nil {
                nativeMarkdownView = NativeMarkdownView(frame: contentView.bounds)
                nativeMarkdownView.autoresizingMask = [.width, .height]
            } else {
                nativeMarkdownView.frame = contentView.bounds
            }
            nativeMarkdownView.setPipeline(preferredNativePipeline)
            view = nativeMarkdownView
        }
        
        rendererView = view
        view.dropDelegate = self
        contentView.addSubview(view)
        
        // 重新顯示目前內容（或歡迎頁）
        if let path = currentFilePath, let content = fileHandler.readFile(at: path) {
            view.setDocumentURL(URL(fileURLWithPath: path))
            view.renderMarkdown(content)
        } else {
            view.setDocumentURL(nil)
            view.loadWelcomePage()
        }
    }
    
    private func setupMenu() {
        menuBuilder = MenuBuilder(appDelegate: self)
        NSApp.mainMenu = menuBuilder.buildMainMenu()
    }
    
    private func setupFileHandler() {
        // fileHandler 已在屬性宣告時初始化
        fileHandler.delegate = self
        
        // 處理啟動前收到的檔案
        if let path = pendingFilePath {
            pendingFilePath = nil
            loadMarkdownFile(path: path)
        }
    }
    
    private func processCommandLineArguments() {
        // 若 AppKit 已透過 openFile（例如 double click 或某些啟動時序）交付檔案，
        // 就不要再重複用 command line 再載入一次，避免監控/渲染被重設兩次。
        if currentFilePath != nil { return }

        // 取第一個「看起來是 Markdown 檔」的參數做為檔案路徑
        // 注意：我們也支援像 --screenshot <out.png> 這種「有 value 的 flag」，
        // 因此不能再用「第一個非 option」的策略，否則會誤把 out.png 當成要開的檔案。
        let args = CommandLine.arguments.dropFirst()
        if let filePath = args.first(where: { arg in
            if arg.hasPrefix("-") { return false }
            let lower = arg.lowercased()
            return lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
        }) {
            loadMarkdownFile(path: filePath)
        }
    }
    
    // MARK: - Public Methods
    
    @objc func loadMarkdownFile(path: String) {
        let absolutePath: String
        if path.hasPrefix("/") {
            absolutePath = path
        } else {
            absolutePath = FileManager.default.currentDirectoryPath + "/" + path
        }
        
        guard let content = fileHandler.readFile(at: absolutePath) else {
            showError("無法讀取檔案: \(absolutePath)")
            return
        }
        
        currentFilePath = absolutePath
        window.title = "Markdown Viewer - \((absolutePath as NSString).lastPathComponent)"
        rendererView?.setDocumentURL(URL(fileURLWithPath: absolutePath))
        rendererView?.renderMarkdown(content)
        
        // 開始監控檔案變更
        fileHandler.startWatching(path: absolutePath)
    }
    
    @objc func reloadCurrentFile() {
        guard let path = currentFilePath else { return }
        loadMarkdownFile(path: path)
    }
    
    @objc func openFile() {
        let panel = NSOpenPanel()
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
        } else {
            panel.allowedFileTypes = ["md", "markdown"]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.loadMarkdownFile(path: url.path)
            }
        }
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "錯誤"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }

    // MARK: - Screenshot (automated GUI verification)

    private func scheduleScreenshotAndExit(outputPath: String, delaySeconds: TimeInterval) {
        // 避免 delay 為負數導致不可預期
        let delay = max(0.0, delaySeconds)
        let url = URL(fileURLWithPath: outputPath)

        // Watchdog：避免在自動化環境卡死（例如某些 AppKit/WKWebView 時序問題）
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        watchdog.schedule(deadline: .now() + 8.0)
        watchdog.setEventHandler {
            print("SCREENSHOT_TIMEOUT \(outputPath)")
            fflush(stdout)
            Darwin._exit(2)
        }
        watchdog.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { Darwin.exit(1) }

            // 確保至少跑過一次 layout/display
            self.window.displayIfNeeded()
            self.window.contentView?.layoutSubtreeIfNeeded()
            self.window.contentView?.displayIfNeeded()

            // WebKit：用 takeSnapshot（更可靠）
            if self.rendererMode == .webKit, let mv = self.markdownView {
                mv.captureSnapshotPNG(to: url) { ok in
                    watchdog.cancel()
                    print(ok ? "SCREENSHOT_OK \(outputPath)" : "SCREENSHOT_FAIL \(outputPath)")
                    fflush(stdout)
                    Darwin.exit(ok ? 0 : 1)
                }
                return
            }

            // Native（或 fallback）：cacheDisplay 成 PNG（同步、無需螢幕錄製權限）
            let ok = self.captureContentViewPNG(to: url)
            watchdog.cancel()
            print(ok ? "SCREENSHOT_OK \(outputPath)" : "SCREENSHOT_FAIL \(outputPath)")
            fflush(stdout)
            Darwin.exit(ok ? 0 : 1)
        }
    }

    private func captureContentViewPNG(to url: URL) -> Bool {
        guard let contentView = window.contentView else { return false }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return false
        }

        let bounds = contentView.bounds
        guard bounds.width > 2, bounds.height > 2 else { return false }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        contentView.cacheDisplay(in: bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - View Menu Actions
    
    @objc func zoomIn() {
        rendererView?.zoomIn()
    }
    
    @objc func zoomOut() {
        rendererView?.zoomOut()
    }
    
    @objc func resetZoom() {
        rendererView?.resetZoom()
    }
    
    // MARK: - Renderer Actions
    
    @objc func useWebKitRenderer() {
        setRenderer(.webKit)
    }
    
    @objc func useNativeRenderer() {
        setRenderer(.native)
    }
    
    // MARK: - Help Menu Actions
    
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Markdown Viewer 說明"
        alert.informativeText = """
        使用方式：
        
        1. 拖放 .md 或 .markdown 檔案到視窗
        2. 使用 File → Open 開啟檔案
        3. 命令列：./mdviewer path/to/file.md
        
        快捷鍵：
        • ⌘O - 開啟檔案
        • ⌘R - 重新載入
        • ⌘+ - 放大
        • ⌘- - 縮小
        • ⌘0 - 實際大小
        • ⌘W - 關閉視窗
        • ⌘Q - 結束程式
        
        功能：
        • 自動偵測檔案變更並重新載入
        • 支援 GitHub Flavored Markdown
        • 程式碼語法高亮
        • 深色模式自動切換
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "確定")
        alert.runModal()
    }
}

// MARK: - MarkdownDropDelegate

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(useWebKitRenderer):
            menuItem.state = (rendererMode == .webKit) ? .on : .off
            return true
        case #selector(useNativeRenderer):
            menuItem.state = (rendererMode == .native) ? .on : .off
            return true
        default:
            return true
        }
    }
}

extension AppDelegate: MarkdownDropDelegate {
    func markdownView(_ view: NSView, didReceiveDroppedFile path: String) {
        loadMarkdownFile(path: path)
    }
}

// MARK: - FileHandlerDelegate

extension AppDelegate: FileHandlerDelegate {
    func fileDidChange(at path: String) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadCurrentFile()
        }
    }
}
