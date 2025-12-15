import AppKit
import Foundation

/// Mermaid fenced code block renderer (optional).
///
/// 預設不強制依賴任何外部工具；若偵測到 `mmdc`（mermaid-cli）可用且啟用 mermaid，
/// 會嘗試把 ` ```mermaid ` 內容轉成 PNG 並以 NSTextAttachment 顯示，否則 fallback 顯示原始碼。
enum MermaidRenderer {
    private static var cachedAvailability: Bool?
    private static let availabilityLock = NSLock()
    private static var imageCache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    static func isEnabled() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["MDVIEWER_MERMAID"] == "1" { return true }
        return CommandLine.arguments.contains("--mermaid")
    }

    static func renderAttachmentIfPossible(code: String, theme: NativeMarkdownTheme, maxWidth: CGFloat?) -> NSAttributedString? {
        guard isEnabled() else { return nil }
        guard isMmdcAvailable() else { return nil }

        let key = cacheKey(code: code, theme: theme, maxWidth: maxWidth)
        if let cached = cachedImage(forKey: key) {
            return attributedAttachment(for: cached, theme: theme, maxWidth: maxWidth)
        }

        guard let img = renderViaMmdc(code: code) else { return nil }
        cacheImage(img, forKey: key)
        return attributedAttachment(for: img, theme: theme, maxWidth: maxWidth)
    }

    // MARK: - Availability

    private static func isMmdcAvailable() -> Bool {
        availabilityLock.lock()
        defer { availabilityLock.unlock() }

        if let cachedAvailability { return cachedAvailability }
        let ok = (runProcessCapture("/usr/bin/env", ["which", "mmdc"], timeoutSeconds: 0.3).terminationStatus == 0)
        cachedAvailability = ok
        return ok
    }

    // MARK: - Render

    private static func renderViaMmdc(code: String) -> NSImage? {
        // 注意：mmdc 可能非常慢（首次跑 puppeteer/Chromium）；避免卡住，給短 timeout，失敗即 fallback。
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mdviewer-mermaid-\(UUID().uuidString)", isDirectory: true)
        let inFile = tmpDir.appendingPathComponent("diagram.mmd")
        let outFile = tmpDir.appendingPathComponent("diagram.png")

        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            try code.write(to: inFile, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        // `mmdc` 參數：避免多餘輸出，並用透明背景
        let result = runProcessCapture(
            "/usr/bin/env",
            ["mmdc", "-i", inFile.path, "-o", outFile.path, "-b", "transparent", "--quiet"],
            timeoutSeconds: 1.2
        )

        guard result.terminationStatus == 0, FileManager.default.fileExists(atPath: outFile.path) else {
            return nil
        }

        return NSImage(contentsOf: outFile)
    }

    private static func attributedAttachment(for image: NSImage, theme: NativeMarkdownTheme, maxWidth: CGFloat?) -> NSAttributedString {
        let attachment = NSTextAttachment()

        // 依可用寬度縮放，避免撐爆 layout
        let wLimit: CGFloat = {
            if let maxWidth { return max(120, maxWidth) }
            return CGFloat(720.0 * theme.zoom)
        }()

        let size = image.size
        if size.width > 0 && size.height > 0 {
            let ratio = min(1.0, wLimit / size.width)
            let displaySize = NSSize(width: size.width * ratio, height: size.height * ratio)
            attachment.bounds = NSRect(x: 0, y: 0, width: displaySize.width, height: displaySize.height)
        }
        attachment.image = image

        return NSAttributedString(attachment: attachment)
    }

    // MARK: - Cache

    private static func cacheKey(code: String, theme: NativeMarkdownTheme, maxWidth: CGFloat?) -> String {
        // zoom 會影響縮放；maxWidth 也會影響顯示大小
        let w = maxWidth ?? -1
        return "z=\(theme.zoom)|w=\(w)|" + code
    }

    private static func cachedImage(forKey key: String) -> NSImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return imageCache[key]
    }

    private static func cacheImage(_ image: NSImage, forKey key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        imageCache[key] = image
    }

    // MARK: - Process helper

    private struct ProcessRunResult {
        let terminationStatus: Int32
        let output: String
    }

    private static func runProcessCapture(_ executablePath: String, _ arguments: [String], timeoutSeconds: TimeInterval) -> ProcessRunResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return ProcessRunResult(terminationStatus: 127, output: "ERROR: failed to run: \(error)")
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while task.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        if task.isRunning {
            task.terminate()
        }

        // 等一點點再讀 output
        let exitDeadline = Date().addingTimeInterval(0.2)
        while task.isRunning && Date() < exitDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessRunResult(terminationStatus: task.terminationStatus, output: output)
    }
}

