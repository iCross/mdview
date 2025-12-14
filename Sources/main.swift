// main.swift
// macOS Markdown Viewer - 應用程式入口點

import AppKit
import Highlightr

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
      --no-activate            不強制把 App 拉到前景（建議在 background job `&` 或某些自動化環境使用）
      --native-pipeline=regex|ast
                              指定 Native Markdown 管線（預設 regex；ast 會在遇到 table/task/image 時 fallback）
      --native-ast             等同 --native-pipeline=ast
      --smoke-test             GUI smoke test（建立視窗後自動退出）
      --screenshot <out.png>   啟動 GUI、渲染後截圖輸出 PNG，然後自動退出
      --screenshot=<out.png>   同上（等號形式）
      --screenshot-full        截「整份文件內容」（可能很大；超出上限會失敗，建議改用 scroll-to）
      --screenshot-scroll-to <text>
                              截圖前先捲到第一個包含 <text> 的位置（用於讓 table/quote 一定在截圖範圍內）
      --screenshot-scroll-y <number>
                              截圖前捲到指定 y offset（點數；0 代表頂端）
      --screenshot-delay <sec> 等待秒數（預設 1.0；WebKit 建議 >= 1.0）
      --screenshot-delay=<sec> 同上（等號形式）

    Debug/Testing:
      --native-dump <file.md>  不啟動 GUI，輸出 Native 解析結果（供測試用）
      --native-render-text <file.md>
                              不啟動 GUI，輸出 Native 渲染後的純文字（供測試用）
      --native-skeleton-check  不啟動 GUI，驗證 NSTextView/NSScrollView 寬度骨架
      --highlightr-check       不啟動 GUI，驗證 Highlightr（bundle resources/JSCore）可用
    """)
}

func parseValueAfterFlag(_ flag: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag) else { return nil }
    let next = idx + 1
    guard next < args.count else { return nil }
    return args[next]
}

func parseNativePipeline(in args: [String]) -> NativeMarkdownPipeline {
    if args.contains("--native-ast") { return .ast }
    if let pipelineArg = args.first(where: { $0.hasPrefix("--native-pipeline=") }) {
        let value = pipelineArg.replacingOccurrences(of: "--native-pipeline=", with: "").lowercased()
        return NativeMarkdownPipeline(rawValue: value) ?? .regex
    }
    return .regex
}

let args = CommandLine.arguments
let nativePipeline = parseNativePipeline(in: args)

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
        print(NativeMarkdownView.debugRenderPlainText(markdown: content, pipeline: nativePipeline))
        exit(0)
    } else {
        print("ERROR: 無法讀取檔案: \(path)")
        exit(2)
    }
}
if args.contains("--native-render-text"), let path = parseValueAfterFlag("--native-render-text", in: args) {
    if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        print(NativeMarkdownView.debugRenderPlainText(markdown: content, pipeline: nativePipeline))
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

// 建立並設定應用程式代理
let delegate = AppDelegate()
app.delegate = delegate

// 讓 bootstrap 發生在 event loop 開始後（更符合 AppKit / WebKit 期望時序）
DispatchQueue.main.async {
    delegate.bootstrapIfNeeded()
}

// 進入 event loop
app.run()
