import AppKit
import Foundation

/// A single Markdown document window (window + renderer view + file watching).
///
/// Goals:
/// - Support multiple windows (open multiple files at once)
/// - Encapsulate "open/reload/watch file changes/drag & drop" in one place
final class MarkdownWindowController: NSObject {
    private(set) var window: NSWindow
    private(set) var rendererView: (NSView & MarkdownRenderable)
    private let fileHandler: FileHandler

    private(set) var currentFilePath: String?

    /// Set by AppDelegate to remove this controller from the centralized list on window close.
    var onClose: ((MarkdownWindowController) -> Void)?

    init(
        initialFilePath: String?,
        preferredNativePipeline: NativeMarkdownPipeline
    ) {
        self.fileHandler = FileHandler()

        // Create the window first (ensure it can always be shown)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let targetWidth: CGFloat = min(visibleFrame.width, min(1200, max(900, visibleFrame.width * 0.8)))
        let targetHeight: CGFloat = min(visibleFrame.height, max(700, visibleFrame.height * 0.95))
        let windowRect = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)

        self.window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.window.isReleasedWhenClosed = false
        self.window.setFrameAutosaveName("MainWindow")
        let didRestoreFrame = self.window.setFrameUsingName("MainWindow")
        if didRestoreFrame {
            let constrained = self.window.constrainFrameRect(self.window.frame, to: NSScreen.main)
            self.window.setFrame(constrained, display: false)
        } else {
            self.window.center()
        }

        // renderer（Native-only）
        let layoutSize = self.window.contentLayoutRect.size
        let fallbackSize = self.window.contentRect(forFrameRect: self.window.frame).size
        let size = (layoutSize.width > 0 && layoutSize.height > 0) ? layoutSize : fallbackSize
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        self.window.contentView = contentView

        let native = NativeMarkdownView(frame: contentView.bounds)
        native.autoresizingMask = [.width, .height]
        native.setPipeline(preferredNativePipeline)
        self.rendererView = native

        super.init()

        self.window.delegate = self
        self.fileHandler.delegate = self

        self.window.registerForDraggedTypes([.fileURL])

        self.rendererView.dropDelegate = self
        contentView.addSubview(self.rendererView)

        if let p = initialFilePath {
            loadMarkdownFile(path: p)
        } else {
            rendererView.setDocumentURL(nil)
            rendererView.loadWelcomePage()
            window.title = "Markdown Viewer"
        }
    }

    func show(activate: Bool) {
        window.makeKeyAndOrderFront(nil)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func loadMarkdownFile(path: String) {
        let absolutePath = fileHandler.resolveAbsolutePath(path)
        guard let content = fileHandler.readFile(at: absolutePath) else {
            showError("Failed to read file: \(absolutePath)")
            return
        }

        currentFilePath = absolutePath
        window.title = (absolutePath as NSString).lastPathComponent
        rendererView.setDocumentURL(URL(fileURLWithPath: absolutePath))
        rendererView.renderMarkdown(content)

        fileHandler.startWatching(path: absolutePath)
    }

    func reloadCurrentFile() {
        guard let path = currentFilePath else { return }
        loadMarkdownFile(path: path)
    }

    func zoomIn() { rendererView.zoomIn() }
    func zoomOut() { rendererView.zoomOut() }
    func resetZoom() { rendererView.resetZoom() }
    func rerender() { rendererView.rerender() }

    @objc func copyFullContent() {
        guard let path = currentFilePath else { return }
        guard let content = fileHandler.readFile(at: path) else {
            showError("Failed to read file: \(path)")
            return
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - NSWindowDelegate

extension MarkdownWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        fileHandler.stopWatching()
        onClose?(self)
    }
}

// MARK: - MarkdownDropDelegate

extension MarkdownWindowController: MarkdownDropDelegate {
    func markdownView(_ view: NSView, didReceiveDroppedFile path: String) {
        loadMarkdownFile(path: path)
    }
}

// MARK: - FileHandlerDelegate

extension MarkdownWindowController: FileHandlerDelegate {
    func fileDidChange(at path: String) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadCurrentFile()
        }
    }
}

