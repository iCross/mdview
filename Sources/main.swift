// main.swift
// macOS Markdown Viewer - Application entry point

import Foundation
import AppKit
import Highlightr

func printHelp() {
    let exe = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "mdview"
    print("""
    Markdown Viewer

    Usage:
      \(exe) [options] [file.md ...]

    Options:
      --help, -h               Show this help and exit
      --wait, --debug          Keep the process attached to this terminal (default: detach and return immediately)
      --no-activate            Do not force the app to the foreground (recommended for background jobs `&` or automation)
      --theme=system|light|dark
                              UI theme (default: system; can also be changed via the menu)
      --pipeline=regex|ast     Markdown pipeline (default: regex; ast will fall back on table/task/image)
      --ast                    Same as --pipeline=ast
      --smoke-test             GUI smoke test (create a window, then exit automatically)
      --screenshot <out.png>   Launch GUI, render, write a PNG screenshot, then exit
      --screenshot=<out.png>   Same as above (equals form)
      --screenshot-full        Capture the full document (may be huge; can fail if too tall—prefer scroll-to)
      --screenshot-scroll-to <text>
                              Scroll to the first occurrence of <text> before capturing (useful for table/quote visibility)
      --screenshot-scroll-y <number>
                              Scroll to a specific y offset (points; 0 = top) before capturing
      --screenshot-delay <sec> Delay in seconds (default: 1.0)
      --screenshot-delay=<sec> Same as above (equals form)

    Debug/Testing:
      --dump <file.md>         Print parse/debug output without launching the GUI (for tests)
      --render-text <file.md>  Print rendered plain text without launching the GUI (for tests)
      --skeleton-check         Verify the NSTextView/NSScrollView width skeleton without launching the GUI
      --highlightr-check       Verify Highlightr (bundle resources/JSCore) without launching the GUI
    """)
}

func parseValueAfterFlag(_ flag: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag) else { return nil }
    let next = idx + 1
    guard next < args.count else { return nil }
    return args[next]
}

enum ThemePreference: String {
    case system
    case light
    case dark
}

func parseThemePreference(in args: [String]) -> ThemePreference {
    // Supports:
    // - --theme=system|light|dark
    // - --theme system|light|dark
    if let arg = args.first(where: { $0.hasPrefix("--theme=") }) {
        let v = arg.replacingOccurrences(of: "--theme=", with: "").lowercased()
        return ThemePreference(rawValue: v) ?? .system
    }
    if args.contains("--theme"), let v = parseValueAfterFlag("--theme", in: args)?.lowercased() {
        return ThemePreference(rawValue: v) ?? .system
    }
    return .system
}

func applyThemePreference(_ pref: ThemePreference) {
    switch pref {
    case .system:
        NSApp.appearance = nil
    case .light:
        NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

func makeDefaultAppIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }
    
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()
    
    // Background: rounded rectangle
    let bg = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.18, yRadius: size * 0.18)
    NSColor(calibratedRed: 0.13, green: 0.24, blue: 0.55, alpha: 1.0).setFill()
    bg.fill()
    
    // Inner stroke: subtle light border
    let stroke = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.18, yRadius: size * 0.18)
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
    stroke.lineWidth = max(2, size * 0.02)
    stroke.stroke()
    
    // Label text: MD
    let title = "MD"
    let font = NSFont.systemFont(ofSize: size * 0.42, weight: .bold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let s = NSAttributedString(string: title, attributes: attrs)
    let textSize = s.size()
    let textRect = NSRect(
        x: (size - textSize.width) / 2.0,
        y: (size - textSize.height) / 2.0 - size * 0.02,
        width: textSize.width,
        height: textSize.height
    )
    s.draw(in: textRect)
    
    return img
}

func parseNativePipeline(in args: [String]) -> NativeMarkdownPipeline {
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

let args = CommandLine.arguments
let nativePipeline = parseNativePipeline(in: args)
let themePreference = parseThemePreference(in: args)
let wantsWait = args.contains("--wait") || args.contains("--debug")
let isChildGUI = args.contains("--child-gui")

if args.contains("--help") || args.contains("-h") {
    printHelp()
    exit(0)
}

// --dump=path or --dump path
if let dumpArg = args.first(where: { $0.hasPrefix("--dump=") }) {
    let path = dumpArg.replacingOccurrences(of: "--dump=", with: "")
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugDump(markdown: content))
        exit(0)
    } else {
        print("ERROR: Failed to read file: \(path)")
        exit(2)
    }
}
if args.contains("--dump"), let path = parseValueAfterFlag("--dump", in: args) {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugDump(markdown: content))
        exit(0)
    } else {
        print("ERROR: Failed to read file: \(path)")
        exit(2)
    }
}

// --render-text=path or --render-text path
if let dumpArg = args.first(where: { $0.hasPrefix("--render-text=") }) {
    let path = dumpArg.replacingOccurrences(of: "--render-text=", with: "")
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugRenderPlainText(markdown: content, pipeline: nativePipeline))
        exit(0)
    } else {
        print("ERROR: Failed to read file: \(path)")
        exit(2)
    }
}
if args.contains("--render-text"), let path = parseValueAfterFlag("--render-text", in: args) {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugRenderPlainText(markdown: content, pipeline: nativePipeline))
        exit(0)
    } else {
        print("ERROR: Failed to read file: \(path)")
        exit(2)
    }
}

if args.contains("--skeleton-check") {
    print(NativeMarkdownView.debugSkeletonCheck())
    exit(0)
}

if args.contains("--highlightr-check") {
    guard let hl = Highlightr() else {
        print("HIGHLIGHTR_FAIL")
        exit(2)
    }
    _ = hl.setTheme(to: "paraiso-light")
    hl.theme.setCodeFont(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
    let sample = "let x = 1\nprint(x)\n"
    if hl.highlight(sample, as: "swift", fastRender: true) != nil {
        print("HIGHLIGHTR_OK")
        exit(0)
    } else {
        print("HIGHLIGHTR_FAIL")
        exit(1)
    }
}

// Check for file existence before launching
let potentialFiles = args.dropFirst().filter { arg in
    if arg.hasPrefix("-") { return false }
    let lower = arg.lowercased()
    return lower.hasSuffix(".md") || lower.hasSuffix(".markdown") || lower.hasSuffix(".txt")
}

if !potentialFiles.isEmpty {
    let handler = FileHandler()
    let fm = FileManager.default
    for fileArg in potentialFiles {
        let absPath = handler.resolveAbsolutePath(fileArg)
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: absPath, isDirectory: &isDir) || isDir.boolValue {
            fputs("Error: File not found: \(fileArg)\n", stderr)
            exit(1)
        }
    }
}

func shouldStayAttachedToTerminal(_ args: [String]) -> Bool {
    if args.contains("--smoke-test") { return true }
    // Screenshot-related workflows are typically used in scripts and should block until completion.
    if args.contains(where: { $0.hasPrefix("--screenshot") }) { return true }
    if args.contains("--screenshot-full") { return true }
    if args.contains("--screenshot-scroll-to") { return true }
    if args.contains("--screenshot-scroll-y") { return true }
    if args.contains(where: { $0.hasPrefix("--screenshot-delay") }) { return true }
    return false
}

func spawnDetachedGUIProcessAndExit() {
    let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let exeURL = URL(fileURLWithPath: args[0], relativeTo: cwdURL).standardizedFileURL

    let child = Process()
    child.executableURL = exeURL
    child.currentDirectoryURL = cwdURL
    child.arguments = Array(args.dropFirst()) + ["--child-gui"]
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice

    do {
        try child.run()
        exit(0)
    } catch {
        // Fallback to foreground mode if we fail to spawn (keeps behavior functional).
        fputs("WARN: Failed to detach GUI process: \(error)\n", stderr)
        return
    }
}

// Default behavior: detach so the terminal returns immediately, similar to `open`.
if !isChildGUI && !wantsWait && !shouldStayAttachedToTerminal(args) {
    spawnDetachedGUIProcessAndExit()
}

// Create the application instance
let app = NSApplication.shared

// Important: when launched from Terminal (not a .app bundle), force `.regular` so the GUI can appear.
app.setActivationPolicy(.regular)

// Theme (apply before creating windows)
applyThemePreference(themePreference)

// Dock icon: avoid showing the default exec icon when not running as a bundle.
app.applicationIconImage = makeDefaultAppIcon(size: 1024)

// Create and set the app delegate
let delegate = AppDelegate()
app.delegate = delegate

// Run bootstrap after the event loop starts (closer to AppKit's expected timing)
DispatchQueue.main.async {
    delegate.bootstrapIfNeeded()
}

// Enter the event loop
app.run()
