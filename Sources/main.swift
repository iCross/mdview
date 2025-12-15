// main.swift
// macOS Markdown Viewer - 應用程式入口點

import AppKit
import Highlightr

func printHelp() {
    let exe = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "mdviewer"
    print("""
    Markdown Viewer

    Usage:
      \(exe) [options] [file.md ...]

    Options:
      --help, -h               顯示此說明並退出
      --no-activate            不強制把 App 拉到前景（建議在 background job `&` 或某些自動化環境使用）
      --theme=system|light|dark
                              介面主題（預設 system；亦可用選單切換）
      --pipeline=regex|ast     Markdown 管線（預設 regex；ast 會在遇到 table/task/image 時 fallback）
      --ast                    等同 --pipeline=ast
      --mermaid                啟用 Mermaid 圖表渲染（需要系統有 mmdc；否則 fallback 顯示原始碼）
      --smoke-test             GUI smoke test（建立視窗後自動退出）
      --screenshot <out.png>   啟動 GUI、渲染後截圖輸出 PNG，然後自動退出
      --screenshot=<out.png>   同上（等號形式）
      --screenshot-full        截「整份文件內容」（可能很大；超出上限會失敗，建議改用 scroll-to）
      --screenshot-scroll-to <text>
                              截圖前先捲到第一個包含 <text> 的位置（用於讓 table/quote 一定在截圖範圍內）
      --screenshot-scroll-y <number>
                              截圖前捲到指定 y offset（點數；0 代表頂端）
      --screenshot-delay <sec> 等待秒數（預設 1.0）
      --screenshot-delay=<sec> 同上（等號形式）

    Debug/Testing:
      --dump <file.md>         不啟動 GUI，輸出解析結果（供測試用）
      --render-text <file.md>  不啟動 GUI，輸出渲染後的純文字（供測試用）
      --skeleton-check         不啟動 GUI，驗證 NSTextView/NSScrollView 寬度骨架
      --highlightr-check       不啟動 GUI，驗證 Highlightr（bundle resources/JSCore）可用
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
    // 支援：
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
    
    // 背景：圓角矩形
    let bg = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.18, yRadius: size * 0.18)
    NSColor(calibratedRed: 0.13, green: 0.24, blue: 0.55, alpha: 1.0).setFill()
    bg.fill()
    
    // 內圈：淺色描邊
    let stroke = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.18, yRadius: size * 0.18)
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
    stroke.lineWidth = max(2, size * 0.02)
    stroke.stroke()
    
    // 標記文字：MD
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

if args.contains("--help") || args.contains("-h") {
    printHelp()
    exit(0)
}

// --dump=path 或 --dump path
if let dumpArg = args.first(where: { $0.hasPrefix("--dump=") }) {
    let path = dumpArg.replacingOccurrences(of: "--dump=", with: "")
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugDump(markdown: content))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}
if args.contains("--dump"), let path = parseValueAfterFlag("--dump", in: args) {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugDump(markdown: content))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}

// --render-text=path 或 --render-text path
if let dumpArg = args.first(where: { $0.hasPrefix("--render-text=") }) {
    let path = dumpArg.replacingOccurrences(of: "--render-text=", with: "")
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugRenderPlainText(markdown: content, pipeline: nativePipeline))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}
if args.contains("--render-text"), let path = parseValueAfterFlag("--render-text", in: args) {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugRenderPlainText(markdown: content, pipeline: nativePipeline))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
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

// 建立應用程式實例
let app = NSApplication.shared

// 重要：非 .app bundle 從 Terminal 啟動時，需強制設為 regular 才會顯示 GUI
app.setActivationPolicy(.regular)

// Theme（需在 window 建立前套用）
applyThemePreference(themePreference)

// Dock icon：避免非 bundle 執行時顯示預設 exec icon
app.applicationIconImage = makeDefaultAppIcon(size: 1024)

// 建立並設定應用程式代理
let delegate = AppDelegate()
app.delegate = delegate

// 讓 bootstrap 發生在 event loop 開始後（更符合 AppKit 期望時序）
DispatchQueue.main.async {
    delegate.bootstrapIfNeeded()
}

// 進入 event loop
app.run()
