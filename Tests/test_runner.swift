#!/usr/bin/env swift
// test_runner.swift
// macOS Markdown Viewer - 測試程式

import Foundation
import Darwin

// MARK: - 測試框架

struct TestResult {
    let name: String
    let passed: Bool
    let message: String
}

class TestRunner {
    var results: [TestResult] = []
    var passed = 0
    var failed = 0
    
    func run(_ name: String, test: () -> Bool, message: String = "") {
        let result = test()
        results.append(TestResult(name: name, passed: result, message: message))
        if result {
            passed += 1
            print("  ✅ \(name)")
        } else {
            failed += 1
            print("  ❌ \(name)\(message.isEmpty ? "" : " - \(message)")")
        }
    }
    
    func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("測試結果: \(passed) 通過, \(failed) 失敗, 共 \(passed + failed) 個測試")
        print(String(repeating: "=", count: 50))
    }
}

// MARK: - Process helper (timeout-safe)

struct ProcessRunResult {
    let terminationStatus: Int32
    let output: String
    let didTimeout: Bool
}

func runProcess(_ executablePath: String, _ arguments: [String], timeoutSeconds: TimeInterval) -> ProcessRunResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executablePath)
    task.arguments = arguments
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    do {
        try task.run()
    } catch {
        return ProcessRunResult(terminationStatus: 127, output: "ERROR: failed to run: \(error)", didTimeout: false)
    }
    
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while task.isRunning && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    
    var didTimeout = false
    if task.isRunning {
        didTimeout = true
        task.terminate()
        
        // 給 terminate 一點時間，若還不退出就 SIGKILL
        let killDeadline = Date().addingTimeInterval(0.5)
        while task.isRunning && Date() < killDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if task.isRunning {
            kill(task.processIdentifier, SIGKILL)
        }
    }
    
    // 等待結束（再給一點緩衝時間）
    let exitDeadline = Date().addingTimeInterval(0.5)
    while task.isRunning && Date() < exitDeadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return ProcessRunResult(terminationStatus: task.terminationStatus, output: output, didTimeout: didTimeout)
}

// MARK: - 檔案系統測試

func testFileSystem(_ runner: TestRunner) {
    print("\n📁 檔案系統測試")
    print(String(repeating: "-", count: 40))
    
    let fm = FileManager.default
    let basePath = fm.currentDirectoryPath
    
    // 測試 Sources 目錄存在
    runner.run("Sources 目錄存在") {
        fm.fileExists(atPath: "\(basePath)/Sources")
    }
    
    // 測試所有必要的 Swift 檔案
    let requiredFiles = [
        "Sources/main.swift",
        "Sources/AppDelegate.swift",
        "Sources/MarkdownView.swift",
        "Sources/NativeMarkdownView.swift",
        "Sources/FileHandler.swift",
        "Sources/MenuBuilder.swift"
    ]
    
    for file in requiredFiles {
        runner.run("\(file) 存在") {
            fm.fileExists(atPath: "\(basePath)/\(file)")
        }
    }
    
    // 測試可執行檔存在
    runner.run("mdviewer 可執行檔存在") {
        fm.fileExists(atPath: "\(basePath)/mdviewer")
    }
    
    // 測試 test.md 存在
    runner.run("test.md 測試檔案存在") {
        fm.fileExists(atPath: "\(basePath)/test.md")
    }
    
    // 測試 Makefile 存在
    runner.run("Makefile 存在") {
        fm.fileExists(atPath: "\(basePath)/Makefile")
    }
    
    // 測試 README.md 存在
    runner.run("README.md 存在") {
        fm.fileExists(atPath: "\(basePath)/README.md")
    }
}

// MARK: - 檔案內容測試

func testFileContents(_ runner: TestRunner) {
    print("\n📄 檔案內容測試")
    print(String(repeating: "-", count: 40))
    
    let basePath = FileManager.default.currentDirectoryPath
    
    // 測試 main.swift 內容
    runner.run("main.swift 包含 NSApplication") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/main.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSApplication") && content.contains("AppDelegate")
    }
    
    // 測試 AppDelegate.swift 內容
    runner.run("AppDelegate.swift 包含必要元件") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/AppDelegate.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSApplicationDelegate") &&
               content.contains("NSWindow") &&
               content.contains("MarkdownView") &&
               content.contains("FileHandler") &&
               content.contains("MenuBuilder")
    }
    
    // 測試 MarkdownView.swift 內容
    runner.run("MarkdownView.swift 包含 WKWebView") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/MarkdownView.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("WKWebView") && content.contains("marked.js") && content.contains("highlight.js")
    }
    
    // 測試 NativeMarkdownView.swift 內容
    runner.run("NativeMarkdownView.swift 包含 NSTextView 原生渲染") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/NativeMarkdownView.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSTextView") && content.contains("NSAttributedString") && content.contains("NativeCodeHighlighter")
    }
    
    // 測試 FileHandler.swift 內容
    runner.run("FileHandler.swift 包含檔案監控") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/FileHandler.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("DispatchSource") && content.contains("readFile")
    }
    
    // 測試 MenuBuilder.swift 內容
    runner.run("MenuBuilder.swift 包含選單建構") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/MenuBuilder.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSMenu") && content.contains("buildMainMenu")
    }
    
    // 測試 test.md 是有效的 Markdown
    runner.run("test.md 包含有效 Markdown 語法") {
        guard let content = try? String(contentsOfFile: "\(basePath)/test.md", encoding: .utf8) else {
            return false
        }
        return content.contains("# ") &&  // 標題
               content.contains("```") &&  // 程式碼區塊
               content.contains("- ") &&   // 列表
               content.contains("|")       // 表格
    }
}

// MARK: - 編譯測試

func testCompilation(_ runner: TestRunner) {
    print("\n🔨 編譯測試")
    print(String(repeating: "-", count: 40))
    
    // 測試可執行檔是否為有效的 Mach-O 二進制檔
    runner.run("mdviewer 是有效的 Mach-O 執行檔") {
        let basePath = FileManager.default.currentDirectoryPath
        let result = runProcess("/usr/bin/file", ["\(basePath)/mdviewer"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("Mach-O") && result.output.contains("executable")
    }
    
    // 測試二進制檔連結的框架
    runner.run("mdviewer 連結 AppKit 框架") {
        let basePath = FileManager.default.currentDirectoryPath
        let result = runProcess("/usr/bin/otool", ["-L", "\(basePath)/mdviewer"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("AppKit")
    }
    
    runner.run("mdviewer 連結 WebKit 框架") {
        let basePath = FileManager.default.currentDirectoryPath
        let result = runProcess("/usr/bin/otool", ["-L", "\(basePath)/mdviewer"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("WebKit")
    }

    // 在某些自動化環境中（例如無 GUI session/WindowServer 或平台限制），
    // AppKit 程式可能會被系統直接 SIGKILL（terminationStatus=9）。
    // 但「直接跳過」會掩蓋本機回歸：因此預設採 FAIL，只有明確設定環境變數才允許 skip。
    let basePath = FileManager.default.currentDirectoryPath
    let allowSkipSubprocess = (ProcessInfo.processInfo.environment["MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS"] == "1")

    let probe = runProcess("\(basePath)/mdviewer", ["--help"], timeoutSeconds: 2.0)
    let canRunMdviewer = !probe.didTimeout && probe.terminationStatus == 0
    if !canRunMdviewer {
        if allowSkipSubprocess {
            print("  ⚠️ 跳過 mdviewer 子行程測試（MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS=1）：status=\(probe.terminationStatus) timeout=\(probe.didTimeout)")
            return
        } else {
            runner.run(
                "mdviewer 子行程可正常啟動（--help）",
                test: { false },
                message: "status=\(probe.terminationStatus) timeout=\(probe.didTimeout)"
            )
            return
        }
    }
    
    // GUI smoke test：確保從 CLI 啟動能建立視窗並自動退出
    runner.run("mdviewer --smoke-test 可正常顯示 GUI 並退出") {
        let result = runProcess("\(basePath)/mdviewer", ["--smoke-test"], timeoutSeconds: 5.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("SMOKE_OK")
    }

    // 背景/子行程環境下，強制 activate 可能導致系統直接打死；因此提供 --no-activate 作保險。
    runner.run("mdviewer --no-activate --smoke-test 可正常退出") {
        let result = runProcess("\(basePath)/mdviewer", ["--no-activate", "--smoke-test"], timeoutSeconds: 5.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("SMOKE_OK")
    }

    // GUI screenshot test：確保能輸出 PNG（用 native renderer 避免 WebKit 非同步造成 flakiness）
    runner.run("mdviewer --native --screenshot 可輸出 PNG 並退出") {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let out = tmpDir.appendingPathComponent("mdviewer-screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: out) }

        let result = runProcess(
            "\(basePath)/mdviewer",
            ["--native", "--screenshot", out.path, "--screenshot-delay", "0.2", "\(basePath)/test.md"],
            timeoutSeconds: 8.0
        )
        guard !result.didTimeout, result.terminationStatus == 0, result.output.contains("SCREENSHOT_OK") else { return false }

        guard FileManager.default.fileExists(atPath: out.path) else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: out.path),
              let size = attrs[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 10_000
    }

    // CLI help：不應啟動 GUI，且應快速退出
    runner.run("mdviewer --help 可正常退出並顯示使用說明") {
        let result = runProcess("\(basePath)/mdviewer", ["--help"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("Usage:") && result.output.contains("--native")
    }

    // Native dump：驗證表格解析至少被觸發（避免「表格不出現」回歸）
    runner.run("mdviewer --native-dump 可解析 test.md 的表格") {
        let result = runProcess("\(basePath)/mdviewer", ["--native-dump", "\(basePath)/test.md"], timeoutSeconds: 2.0)
        let output = result.output
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("[[TABLE]]") &&
               output.contains("功能") &&
               output.contains("狀態") &&
               output.contains("備註")
    }

    runner.run("mdviewer --native-dump 可偵測圖片語法") {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tmpFile = tmpDir.appendingPathComponent("mdviewer-native-dump-image-test.md")
        let markdown = "![icon](./nonexistent.png)\n"
        
        do {
            try markdown.write(to: tmpFile, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        
        let basePath = FileManager.default.currentDirectoryPath
        let result = runProcess("\(basePath)/mdviewer", ["--native-dump", tmpFile.path], timeoutSeconds: 2.0)
        let output = result.output
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("[[IMAGE]]") &&
               output.contains("icon") &&
               output.contains("./nonexistent.png")
    }
    
    // Native render text：驗證 fenced code block 結束後，後續段落仍會被渲染（回歸：JS 區塊後面沒顯示）
    runner.run("mdviewer --native-render-text 不會吃掉 fenced code block 後的內容") {
        let result = runProcess("\(basePath)/mdviewer", ["--native-render-text", "\(basePath)/test.md"], timeoutSeconds: 2.0)
        let output = result.output
        
        // JavaScript code block 後面 test.md 會出現「表格範例」「引用區塊」「待辦清單」
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("表格範例") &&
               output.contains("引用區塊") &&
               output.contains("待辦清單")
    }

    // AST pipeline：至少應能啟動並在遇到 table/task/image 時自動 fallback（不應影響輸出）
    runner.run("mdviewer --native-pipeline=ast --native-render-text 可正常輸出") {
        let result = runProcess("\(basePath)/mdviewer", ["--native-pipeline=ast", "--native-render-text", "\(basePath)/test.md"], timeoutSeconds: 2.0)
        let output = result.output
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("表格範例") &&
               output.contains("引用區塊") &&
               output.contains("待辦清單")
    }

    // Native skeleton：驗證 NSTextView/NSScrollView 寬度骨架會正確同步（避免回歸成每字換行）
    runner.run("mdviewer --native-skeleton-check 會回傳 SKELETON_OK") {
        let result = runProcess("\(basePath)/mdviewer", ["--native-skeleton-check"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("SKELETON_OK")
    }

    // Highlightr：驗證 SPM resource bundle + JSCore 可正常使用
    runner.run("mdviewer --highlightr-check 會回傳 HIGHLIGHTR_OK") {
        let result = runProcess("\(basePath)/mdviewer", ["--highlightr-check"], timeoutSeconds: 4.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("HIGHLIGHTR_OK")
    }
}

// MARK: - FileHandler 單元測試

func testFileHandler(_ runner: TestRunner) {
    print("\n📂 FileHandler 功能測試")
    print(String(repeating: "-", count: 40))
    
    let basePath = FileManager.default.currentDirectoryPath
    let testFilePath = "\(basePath)/test.md"
    
    // 模擬 FileHandler 的檔案讀取邏輯
    runner.run("讀取存在的檔案") {
        let url = URL(fileURLWithPath: testFilePath)
        do {
            let _ = try String(contentsOf: url, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
    
    runner.run("讀取不存在的檔案回傳 nil") {
        let url = URL(fileURLWithPath: "/nonexistent/file.md")
        do {
            let _ = try String(contentsOf: url, encoding: .utf8)
            return false  // 不應該成功
        } catch {
            return true   // 應該拋出錯誤
        }
    }
    
    runner.run("檢測 .md 副檔名") {
        let path = "test.md"
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md"
    }
    
    runner.run("檢測 .markdown 副檔名") {
        let path = "readme.markdown"
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "markdown"
    }
    
    runner.run("解析相對路徑") {
        let relativePath = "test.md"
        let absolutePath: String
        if relativePath.hasPrefix("/") {
            absolutePath = relativePath
        } else {
            absolutePath = FileManager.default.currentDirectoryPath + "/" + relativePath
        }
        return absolutePath.hasPrefix("/") && absolutePath.hasSuffix("test.md")
    }
    
    runner.run("解析絕對路徑") {
        let absoluteInput = "/Users/test/file.md"
        let result: String
        if absoluteInput.hasPrefix("/") {
            result = absoluteInput
        } else {
            result = FileManager.default.currentDirectoryPath + "/" + absoluteInput
        }
        return result == "/Users/test/file.md"
    }
    
    runner.run("取得檔案名稱") {
        let path = "/path/to/file.md"
        let filename = (path as NSString).lastPathComponent
        return filename == "file.md"
    }
    
    runner.run("取得目錄路徑") {
        let path = "/path/to/file.md"
        let directory = (path as NSString).deletingLastPathComponent
        return directory == "/path/to"
    }
}

// MARK: - Markdown 渲染測試

func testMarkdownRendering(_ runner: TestRunner) {
    print("\n📝 Markdown 渲染邏輯測試")
    print(String(repeating: "-", count: 40))
    
    // 測試 JavaScript 字串轉義邏輯
    runner.run("轉義反斜線") {
        let input = "test\\path"
        let escaped = input.replacingOccurrences(of: "\\", with: "\\\\")
        return escaped == "test\\\\path"
    }
    
    runner.run("轉義反引號") {
        let input = "code `block`"
        let escaped = input.replacingOccurrences(of: "`", with: "\\`")
        return escaped == "code \\`block\\`"
    }
    
    runner.run("轉義錢字號") {
        let input = "price $100"
        let escaped = input.replacingOccurrences(of: "$", with: "\\$")
        return escaped == "price \\$100"
    }
    
    runner.run("轉義換行符號") {
        let input = "line1\nline2"
        let escaped = input.replacingOccurrences(of: "\n", with: "\\n")
        return escaped == "line1\\nline2"
    }
    
    // 完整轉義測試
    runner.run("完整 JavaScript 轉義") {
        let input = "Test `code` with $var and\nnewline"
        let escaped = input
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
        return escaped == "Test \\`code\\` with \\$var and\\nnewline"
    }
}

// MARK: - Makefile 測試

func testMakefile(_ runner: TestRunner) {
    print("\n⚙️ Makefile 測試")
    print(String(repeating: "-", count: 40))
    
    let basePath = FileManager.default.currentDirectoryPath
    
    guard let makefileContent = try? String(contentsOfFile: "\(basePath)/Makefile", encoding: .utf8) else {
        runner.run("Makefile 可讀取") { false }
        return
    }
    
    runner.run("Makefile 定義 APP_NAME") {
        makefileContent.contains("APP_NAME")
    }
    
    runner.run("Makefile 定義 SOURCES") {
        makefileContent.contains("SOURCES")
    }
    
    runner.run("Makefile 定義 debug 目標") {
        makefileContent.contains("debug:")
    }
    
    runner.run("Makefile 定義 release 目標") {
        makefileContent.contains("release:")
    }
    
    runner.run("Makefile 定義 clean 目標") {
        makefileContent.contains("clean:")
    }
    
    runner.run("Makefile 包含 AppKit 框架") {
        makefileContent.contains("-framework AppKit")
    }
    
    runner.run("Makefile 包含 WebKit 框架") {
        makefileContent.contains("-framework WebKit")
    }
}

// MARK: - Main

print("""

╔══════════════════════════════════════════════════╗
║     macOS Markdown Viewer - 測試套件             ║
╚══════════════════════════════════════════════════╝
""")

let runner = TestRunner()

testFileSystem(runner)
testFileContents(runner)
testCompilation(runner)
testFileHandler(runner)
testMarkdownRendering(runner)
testMakefile(runner)

runner.printSummary()

// 回傳結束代碼
exit(runner.failed > 0 ? 1 : 0)
