// main.swift
// macOS Markdown Viewer - 應用程式入口點

import AppKit

func printHelp() {
    let exe = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "mdviewer"
    print("""
    Markdown Viewer

    Usage:
      \(exe) [options] [file.md]

    Options:
      --help, -h               顯示此說明並退出
      --native                 使用原生渲染器（NSTextView）
      --webkit                 使用 WebKit 渲染器（預設）
      --renderer=native|webkit 指定渲染器
      --smoke-test             GUI smoke test（建立視窗後自動退出）

    Debug/Testing:
      --native-dump <file.md>  不啟動 GUI，輸出 Native 解析結果（供測試用）
      --native-render-text <file.md>
                              不啟動 GUI，輸出 Native 渲染後的純文字（供測試用）
      --native-skeleton-check  不啟動 GUI，驗證 NSTextView/NSScrollView 寬度骨架
    """)
}

func parseValueAfterFlag(_ flag: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag) else { return nil }
    let next = idx + 1
    guard next < args.count else { return nil }
    return args[next]
}

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    printHelp()
    exit(0)
}

// --native-dump=path 或 --native-dump path
if let dumpArg = args.first(where: { $0.hasPrefix("--native-dump=") }) {
    let path = dumpArg.replacingOccurrences(of: "--native-dump=", with: "")
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugDump(markdown: content))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}
if args.contains("--native-dump"), let path = parseValueAfterFlag("--native-dump", in: args) {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugDump(markdown: content))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}

// --native-render-text=path 或 --native-render-text path
if let dumpArg = args.first(where: { $0.hasPrefix("--native-render-text=") }) {
    let path = dumpArg.replacingOccurrences(of: "--native-render-text=", with: "")
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugRenderPlainText(markdown: content))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}
if args.contains("--native-render-text"), let path = parseValueAfterFlag("--native-render-text", in: args) {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugRenderPlainText(markdown: content))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}

if args.contains("--native-skeleton-check") {
    print(NativeMarkdownView.debugSkeletonCheck())
    exit(0)
}

// 建立應用程式實例
let app = NSApplication.shared

// 重要：非 .app bundle 從 Terminal 啟動時，需強制設為 regular 才會顯示 GUI
app.setActivationPolicy(.regular)

// 建立並設定應用程式代理
let delegate = AppDelegate()
app.delegate = delegate

// 讓 bootstrap 發生在 event loop 開始後（更符合 AppKit / WebKit 期望時序）
DispatchQueue.main.async {
    delegate.bootstrapIfNeeded()
}

// 進入 event loop
app.run()
