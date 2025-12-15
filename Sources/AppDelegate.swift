// AppDelegate.swift
// macOS Markdown Viewer - 應用程式代理
import AppKit
import Foundation
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    var menuBuilder: MenuBuilder!
    
    private var windowControllers: [MarkdownWindowController] = []
    private var pendingFilePaths: [String] = []  // 儲存啟動前收到的檔案路徑（可能多個）
    
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

    private var screenshotIsFull: Bool {
        CommandLine.arguments.contains("--screenshot-full")
    }

    private func parseValueAfterFlag(_ flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let next = idx + 1
        guard next < args.count else { return nil }
        let v = args[next]
        return v.hasPrefix("-") ? nil : v
    }

    private var screenshotScrollToText: String? {
        // 支援：
        // - --screenshot-scroll-to <text>
        // - --screenshot-scroll-to=<text>
        let args = CommandLine.arguments
        if let arg = args.first(where: { $0.hasPrefix("--screenshot-scroll-to=") }) {
            let v = arg.replacingOccurrences(of: "--screenshot-scroll-to=", with: "")
            return v.isEmpty ? nil : v
        }
        if args.contains("--screenshot-scroll-to"), let v = parseValueAfterFlag("--screenshot-scroll-to", in: args) {
            return v
        }
        return nil
    }

    private var screenshotScrollY: CGFloat? {
        // 支援：
        // - --screenshot-scroll-y <number>
        // - --screenshot-scroll-y=<number>
        let args = CommandLine.arguments
        if let arg = args.first(where: { $0.hasPrefix("--screenshot-scroll-y=") }) {
            let v = arg.replacingOccurrences(of: "--screenshot-scroll-y=", with: "")
            if v.isEmpty { return nil }
            if let d = Double(v) { return CGFloat(d) }
            return nil
        }
        if args.contains("--screenshot-scroll-y"), let v = parseValueAfterFlag("--screenshot-scroll-y", in: args) {
            if let d = Double(v) { return CGFloat(d) }
            return nil
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

    private var preferredNativePipeline: NativeMarkdownPipeline {
        // 支援：
        // - --pipeline=regex|ast
        // - --ast（等同 --pipeline=ast）
        let args = CommandLine.arguments
        if let pipelineArg = args.first(where: { $0.hasPrefix("--pipeline=") }) {
            let value = pipelineArg.replacingOccurrences(of: "--pipeline=", with: "").lowercased()
            return NativeMarkdownPipeline(rawValue: value) ?? .regex
        }
        if args.contains("--pipeline"), let v = parseValueAfterFlag("--pipeline", in: args)?.lowercased() {
            return NativeMarkdownPipeline(rawValue: v) ?? .regex
        }
        if args.contains("--ast") { return .ast }
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

        // CLI smoke test：不初始化 renderer，單純驗證「能顯示 GUI + 正常退出」
        if isSmokeTestMode {
            // 這裡不要依賴 timer（在某些自動化/無前景情境 timer 可能不觸發，會導致測試卡住）
            let w = makeSmokeTestWindow()
            w.makeKeyAndOrderFront(nil)
            let ok = w.isVisible && (NSApp.activationPolicy() == .regular)
            print(ok ? "SMOKE_OK" : "SMOKE_FAIL")
            fflush(stdout)
            Darwin.exit(ok ? 0 : 1)
        }

        // 其餘初始化放到下一個 tick，讓 AppKit event loop 穩定後再碰 renderer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupMenu()
            self.processPendingAndCommandLineFiles()

            // GUI 截圖模式：渲染後自動輸出 PNG 並退出（供測試/agent 使用）
            if let outPath = self.screenshotOutputPath, let controller = self.windowControllers.first {
                self.scheduleScreenshotAndExit(controller: controller, outputPath: outPath, delaySeconds: self.screenshotDelaySeconds)
            }
        }
    }
    
    private func shouldActivateAppInThisSession() -> Bool {
        // 在某些環境（例如被當成 background job `&` 啟動，或在無互動 TTY 的子行程中）
        // 強制 activate 可能會被系統拒絕，甚至直接 SIGKILL。
        // 策略：只有「前景互動 TTY」才 activate；否則安靜地跳過。
        if isAutomationMode { return false }
        if CommandLine.arguments.contains("--no-activate") { return false }

        // 若 stdin 不是 TTY（例如被 CI/測試 runner 啟動），就不要 activate。
        if isatty(STDIN_FILENO) == 0 { return false }

        // 若不是 controlling terminal 的前景 process group（典型：`cmd &` 背景 job），不要 activate。
        let fg = tcgetpgrp(STDIN_FILENO)
        if fg == -1 { return false }
        return fg == getpgrp()
    }
    
    // MARK: - Theme
    
    private enum ThemePreference: String {
        case system
        case light
        case dark
    }
    
    private func currentThemePreference() -> ThemePreference {
        // 若沒有強制 appearance，就視為 system
        guard let appearance = NSApp.appearance else { return .system }
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .dark
        } else {
            return .light
        }
    }
    
    private func applyTheme(_ pref: ThemePreference) {
        switch pref {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        
        // Highlightr theme 會在 render 當下依 effectiveAppearance 選擇，因此需要 rerender 才能切換。
        for c in windowControllers {
            c.rerender()
        }
    }
    
    @objc func setThemeSystem() { applyTheme(.system) }
    @objc func setThemeLight() { applyTheme(.light) }
    @objc func setThemeDark() { applyTheme(.dark) }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        // AppKit 可能會把某些「非 option 的 argv」也當成 openFile 事件丟進來；
        // 這裡只接受 Markdown，避免例如 `--screenshot <out.png>` 的 out path 被誤當成要開的文件。
        let lower = filename.lowercased()
        let isMarkdown = lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
        if !isMarkdown { return false }

        // 可能一次收到多個 openFile（例如 Finder 選多檔），因此用 array。
        if !didBootstrap || windowControllers.isEmpty {
            pendingFilePaths.append(filename)
        } else {
            openNewWindow(path: filename, makeKey: true)
        }
        return true
    }
    
    // MARK: - Setup Methods
    
    private func setupMenu() {
        menuBuilder = MenuBuilder(appDelegate: self)
        NSApp.mainMenu = menuBuilder.buildMainMenu()
    }
    
    private func makeSmokeTestWindow() -> NSWindow {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let windowRect = NSRect(x: 0, y: 0, width: min(900, visibleFrame.width), height: min(700, visibleFrame.height))
        let w = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Markdown Viewer"
        w.center()
        w.contentView = NSView(frame: windowRect)
        return w
    }
    
    private func activeWindowController() -> MarkdownWindowController? {
        if let key = NSApp.keyWindow {
            return windowControllers.first(where: { $0.window === key }) ?? windowControllers.first
        }
        return windowControllers.first
    }
    
    private func openNewWindow(path: String?, makeKey: Bool) {
        let controller = MarkdownWindowController(
            initialFilePath: path,
            preferredNativePipeline: preferredNativePipeline
        )
        controller.onClose = { [weak self] c in
            guard let self else { return }
            self.windowControllers.removeAll(where: { $0 === c })
        }
        windowControllers.append(controller)
        
        let shouldActivate = (!isAutomationMode) && shouldActivateAppInThisSession()
        controller.show(activate: makeKey && shouldActivate)
    }
    
    private func processPendingAndCommandLineFiles() {
        // screenshot 模式：只開第一個檔案，避免多視窗干擾截圖目標
        let isScreenshot = (screenshotOutputPath != nil)
        
        // 先處理 AppKit openFile 帶進來的檔案（可能多個）
        var toOpen: [String] = []
        if !pendingFilePaths.isEmpty {
            toOpen.append(contentsOf: pendingFilePaths)
            pendingFilePaths.removeAll(keepingCapacity: true)
        }
        
        // 再處理 CLI 參數帶的檔案（可能多個）
        let cli = CommandLine.arguments.dropFirst()
        let cliFiles = cli.compactMap { arg -> String? in
            if arg.hasPrefix("-") { return nil }
            let lower = arg.lowercased()
            return (lower.hasSuffix(".md") || lower.hasSuffix(".markdown")) ? String(arg) : nil
        }
        toOpen.append(contentsOf: cliFiles)
        
        // 去重（避免同一路徑在 openFile + CLI 都出現）
        var seen = Set<String>()
        toOpen = toOpen.filter { p in
            let abs = FileHandler().resolveAbsolutePath(p)
            if seen.contains(abs) { return false }
            seen.insert(abs)
            return true
        }
        
        if isScreenshot {
            // 僅挑第一個 Markdown 檔；若沒有就顯示 welcome page 仍可截圖（但通常測試會帶 md）
            if let firstMarkdown = toOpen.first(where: { p in
                let lower = p.lowercased()
                return lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
            }) {
                openNewWindow(path: firstMarkdown, makeKey: true)
            } else {
                openNewWindow(path: nil, makeKey: true)
            }
            return
        }
        
        if toOpen.isEmpty {
            openNewWindow(path: nil, makeKey: true)
        } else {
            for (idx, p) in toOpen.enumerated() {
                openNewWindow(path: p, makeKey: idx == 0)
            }
        }
    }
    
    // MARK: - Public Methods
    
    @objc func loadMarkdownFile(path: String) {
        // 為了相容舊路徑：預設載入到目前 key window；若沒有，就開新視窗。
        if let c = activeWindowController() {
            c.loadMarkdownFile(path: path)
        } else {
            openNewWindow(path: path, makeKey: true)
        }
    }
    
    @objc func reloadCurrentFile() {
        activeWindowController()?.reloadCurrentFile()
    }
    
    @objc func openFile() {
        let panel = NSOpenPanel()
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
        } else {
            panel.allowedFileTypes = ["md", "markdown"]
        }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        
        panel.begin { [weak self] response in
            guard let self else { return }
            if response == .OK {
                let urls = panel.urls
                for (idx, url) in urls.enumerated() {
                    self.openNewWindow(path: url.path, makeKey: idx == 0)
                }
            }
        }
    }

    // MARK: - Screenshot (automated GUI verification)

    private func scheduleScreenshotAndExit(controller: MarkdownWindowController, outputPath: String, delaySeconds: TimeInterval) {
        // 避免 delay 為負數導致不可預期
        let delay = max(0.0, delaySeconds)
        let url = URL(fileURLWithPath: outputPath)

        // Watchdog：避免在自動化環境卡死（例如某些 AppKit 時序問題）
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        watchdog.schedule(deadline: .now() + 12.0)
        watchdog.setEventHandler {
            print("SCREENSHOT_TIMEOUT \(outputPath)")
            fflush(stdout)
            Darwin._exit(2)
        }
        watchdog.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { Darwin.exit(1) }

            // 確保至少跑過一次 layout/display
            let window = controller.window
            window.displayIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()

            let native = controller.rendererView as? NativeMarkdownView

            // Native：cacheDisplay 成 PNG（同步、無需螢幕錄製權限）
            if let t = self.screenshotScrollToText {
                let found = native?.scrollToFirstOccurrence(of: t) ?? false
                if !found {
                    watchdog.cancel()
                    print("SCREENSHOT_SCROLL_TO_NOT_FOUND \(t) \(outputPath)")
                    fflush(stdout)
                    Darwin.exit(1)
                }
                window.displayIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
            } else if let y = self.screenshotScrollY {
                native?.scrollTo(y: y)
                window.displayIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
            }

            let ok: Bool
            if self.screenshotIsFull, let native {
                let fullView = native.viewForFullScreenshot()
                let bounds = fullView.bounds
                let maxHeight: CGFloat = 12_000
                if bounds.height > maxHeight {
                    print("SCREENSHOT_TOO_TALL height=\(bounds.height) max=\(maxHeight) (use --screenshot-scroll-to) \(outputPath)")
                    ok = false
                } else {
                    ok = self.captureViewPNG(fullView, bounds: bounds, to: url)
                }
            } else {
                ok = self.captureContentViewPNG(window: window, to: url)
            }

            watchdog.cancel()
            print(ok ? "SCREENSHOT_OK \(outputPath)" : "SCREENSHOT_FAIL \(outputPath)")
            fflush(stdout)
            Darwin.exit(ok ? 0 : 1)
        }
    }

    private func captureContentViewPNG(window: NSWindow, to url: URL) -> Bool {
        guard let contentView = window.contentView else { return false }

        return captureViewPNG(contentView, bounds: contentView.bounds, to: url)
    }

    private func captureViewPNG(_ view: NSView, bounds: CGRect, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return false
        }

        guard bounds.width > 2, bounds.height > 2 else { return false }

        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)

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
        activeWindowController()?.zoomIn()
    }
    
    @objc func zoomOut() {
        activeWindowController()?.zoomOut()
    }
    
    @objc func resetZoom() {
        activeWindowController()?.resetZoom()
    }
    
    // MARK: - Renderer Actions

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

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Theme radio-like state
        if menuItem.action == #selector(setThemeSystem) {
            menuItem.state = (currentThemePreference() == .system) ? .on : .off
        } else if menuItem.action == #selector(setThemeLight) {
            menuItem.state = (currentThemePreference() == .light) ? .on : .off
        } else if menuItem.action == #selector(setThemeDark) {
            menuItem.state = (currentThemePreference() == .dark) ? .on : .off
        }
        return true
    }
}
