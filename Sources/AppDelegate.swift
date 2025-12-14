// AppDelegate.swift
// macOS Markdown Viewer - 應用程式代理

import AppKit

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
        showWindowNow()

        // CLI smoke test：不初始化 WebKit，單純驗證「能顯示 GUI + 正常退出」
        if isSmokeTestMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { Darwin.exit(1) }
                let ok = (self.window != nil) && self.window.isVisible && (NSApp.activationPolicy() == .regular)
                print(ok ? "SMOKE_OK" : "SMOKE_FAIL")
                Darwin.exit(ok ? 0 : 1)
            }
            return
        }

        // 其餘初始化放到下一個 tick，讓 AppKit event loop 穩定後再碰 WebKit
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupMarkdownView()
            self.setupMenu()
            self.setupFileHandler()
            self.processCommandLineArguments()
        }
    }
    
    private func showWindowNow() {
        // 若 contentView 尚未建立，補一個避免後續 force unwrap
        if window.contentView == nil {
            window.contentView = NSView(frame: window.frame)
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
        NSApp.activate(ignoringOtherApps: true)
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
        // 計算視窗位置（螢幕中央）
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let windowWidth: CGFloat = 900
        let windowHeight: CGFloat = 700
        let windowX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
        let windowY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2
        
        let windowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Markdown Viewer"
        window.minSize = NSSize(width: 400, height: 300)
        window.isReleasedWhenClosed = false
        
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
        // 取第一個「不是 option」的參數做為檔案路徑
        let args = CommandLine.arguments.dropFirst()
        if let filePath = args.first(where: { !$0.hasPrefix("-") }) {
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
