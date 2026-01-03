// AppDelegate.swift
// macOS Markdown Viewer - Application delegate
import AppKit
import Foundation
import Darwin

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    var menuBuilder: MenuBuilder!
    
    private var windowControllers: [MarkdownWindowController] = []
    private var pendingFilePaths: [String] = []  // File paths received before bootstrap (can be multiple)
    
    private var isSmokeTestMode: Bool {
        CommandLine.arguments.contains("--smoke-test")
    }

    private var isAutomationMode: Bool {
        // For CI/automation: avoid foreground behaviors that may hang or be rejected (e.g. activate)
        isSmokeTestMode || (screenshotOutputPath != nil)
    }

    private var screenshotOutputPath: String? {
        // Supports:
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
        // Supports:
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
        // Supports:
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
        // Supports: --screenshot-delay=1.2 or --screenshot-delay 1.2
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
        // Supports:
        // - --pipeline=regex|ast
        // - --ast (same as --pipeline=ast)
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
        
        IPC.startServer { [weak self] paths in
            guard let self = self else { return }
            NSApp.activate(ignoringOtherApps: true)
            
            for path in paths {
                self.openNewWindow(path: path, makeKey: true)
            }
        }
    }
    
    /// Used for the "not a .app bundle, executed directly from CLI" launch path:
    /// in some situations AppKit's launch callback timing can be unstable and the window may not appear.
    /// This makes the bootstrap flow re-entrant and manually triggerable, ensuring the GUI shows reliably.
    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        
        // Extra safety: ensure this is a regular GUI app (especially important when launched from Terminal without a bundle)
        NSApp.setActivationPolicy(.regular)

        // CLI smoke test: don't initialize the renderer; only verify "GUI can show + exits cleanly"
        if isSmokeTestMode {
            // Don't rely on a timer here (in some automation/no-foreground scenarios timers may not fire and tests can hang)
            let w = makeSmokeTestWindow()
            w.makeKeyAndOrderFront(nil)
            let ok = w.isVisible && (NSApp.activationPolicy() == .regular)
            print(ok ? "SMOKE_OK" : "SMOKE_FAIL")
            fflush(stdout)
            Darwin.exit(ok ? 0 : 1)
        }

        // Defer the rest to the next tick so AppKit's event loop is stable before touching the renderer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupMenu()
            self.processPendingAndCommandLineFiles()

            // GUI screenshot mode: render, write a PNG, then exit (for tests/agents)
            if let outPath = self.screenshotOutputPath, let controller = self.windowControllers.first {
                self.scheduleScreenshotAndExit(controller: controller, outputPath: outPath, delaySeconds: self.screenshotDelaySeconds)
            }
        }
    }
    
    private func shouldActivateAppInThisSession() -> Bool {
        // In some environments (e.g. launched as a background job `&`, or in a non-interactive subprocess),
        // forcing activation can be rejected by the system, or even lead to SIGKILL.
        // Policy: only activate for a foreground interactive TTY; otherwise, silently skip.
        if isAutomationMode { return false }
        if CommandLine.arguments.contains("--no-activate") { return false }

        // Detached child process spawned by the parent should always activate (user explicitly launched it).
        if CommandLine.arguments.contains("--child-gui") { return true }

        // If stdin is not a TTY (e.g. launched by CI/test runner), don't activate.
        if isatty(STDIN_FILENO) == 0 { return false }

        // If we're not the foreground process group of the controlling terminal (typical `cmd &`), don't activate.
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
        // If appearance isn't forced, treat it as system.
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
        
        // Highlightr picks its theme at render time from `effectiveAppearance`, so we need to rerender to apply changes.
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
        // AppKit may feed some "non-option argv" as `openFile` events.
        // Only accept Markdown and text files here; otherwise a path like `--screenshot <out.png>` could be misinterpreted as a document.
        let lower = filename.lowercased()
        let isSupported = lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".txt")
        if !isSupported { return false }

        // We may receive multiple `openFile` calls (e.g. multi-select in Finder), so keep an array.
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
        // Screenshot mode: only open the first file to avoid multiple windows interfering with the target capture.
        let isScreenshot = (screenshotOutputPath != nil)
        
        // First, process files provided via AppKit openFile (can be multiple).
        var toOpen: [String] = []
        if !pendingFilePaths.isEmpty {
            toOpen.append(contentsOf: pendingFilePaths)
            pendingFilePaths.removeAll(keepingCapacity: true)
        }
        
        // Then, process files from CLI args (can be multiple).
        let cli = CommandLine.arguments.dropFirst()
        let cliFiles = cli.compactMap { arg -> String? in
            if arg.hasPrefix("-") { return nil }
            let lower = arg.lowercased()
            return (lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".txt")) ? String(arg) : nil
        }
        toOpen.append(contentsOf: cliFiles)
        
        // De-duplicate (avoid the same path appearing in both openFile + CLI).
        var seen = Set<String>()
        toOpen = toOpen.filter { p in
            let abs = FileHandler().resolveAbsolutePath(p)
            if seen.contains(abs) { return false }
            seen.insert(abs)
            return true
        }
        
        if isScreenshot {
            // Pick only the first supported file; if none, show the welcome page (still screenshot-able).
            if let firstMarkdown = toOpen.first(where: { p in
                let lower = p.lowercased()
                return lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".txt")
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
        // Compatibility behavior: load into the current key window by default; if none, open a new window.
        if let c = activeWindowController() {
            c.loadMarkdownFile(path: path)
        } else {
            openNewWindow(path: path, makeKey: true)
        }
    }
    
    @objc func reloadCurrentFile() {
        activeWindowController()?.reloadCurrentFile()
    }

    @objc func copyFullContent() {
        activeWindowController()?.copyFullContent()
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
        // Guard against negative delay.
        let delay = max(0.0, delaySeconds)
        let url = URL(fileURLWithPath: outputPath)

        // Watchdog: avoid hanging in automation environments (e.g. AppKit timing issues).
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

            // Ensure we ran at least one layout/display pass.
            let window = controller.window
            window.displayIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()

            let native = controller.rendererView as? NativeMarkdownView

            // Native: cacheDisplay to PNG (sync, no screen recording permission required).
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
        alert.messageText = "Markdown Viewer Help"
        alert.informativeText = """
        How to use:
        
        1. Drag and drop a `.md` or `.markdown` file onto the window
        2. Use File → Open… to open a file
        3. Command line: `./mdview path/to/file.md`
        
        Keyboard shortcuts:
        • ⌘O - Open…
        • ⌘R - Reload
        • ⌘+ - Zoom in
        • ⌘- - Zoom out
        • ⌘0 - Actual size
        • ⌘W - Close window
        • ⌘Q - Quit
        
        Features:
        • Auto-reload on file changes
        • GitHub Flavored Markdown support
        • Syntax highlighting
        • Automatic dark mode support
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
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
        } else if menuItem.action == #selector(copyFullContent) {
            return activeWindowController()?.currentFilePath != nil
        }
        return true
    }
}
