#!/usr/bin/env swift
// test_runner.swift
// macOS Markdown Viewer - Test runner

import Foundation
import Darwin
import Compression

// MARK: - Test framework

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
        print("Test results: \(passed) passed, \(failed) failed, total \(passed + failed)")
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
        
        // Give terminate a moment; if it's still running, SIGKILL.
        let killDeadline = Date().addingTimeInterval(0.5)
        while task.isRunning && Date() < killDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if task.isRunning {
            kill(task.processIdentifier, SIGKILL)
        }
    }
    
    // Wait for exit (extra grace period)
    let exitDeadline = Date().addingTimeInterval(0.5)
    while task.isRunning && Date() < exitDeadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return ProcessRunResult(terminationStatus: task.terminationStatus, output: output, didTimeout: didTimeout)
}

// MARK: - File system tests

func testFileSystem(_ runner: TestRunner) {
    print("\n📁 File system tests")
    print(String(repeating: "-", count: 40))
    
    let fm = FileManager.default
    let basePath = fm.currentDirectoryPath
    
    // Sources directory exists
    runner.run("Sources directory exists") {
        fm.fileExists(atPath: "\(basePath)/Sources")
    }
    
    // All required Swift files exist
    let requiredFiles = [
        "Sources/main.swift",
        "Sources/AppDelegate.swift",
        "Sources/MarkdownRenderable.swift",
        "Sources/MarkdownWindowController.swift",
        "Sources/NativeMarkdownView.swift",
        "Sources/ASTMarkdownRenderer.swift",
        "Sources/MermaidRenderer.swift",
        "Sources/RemoteImageAttachment.swift",
        "Sources/FileHandler.swift",
        "Sources/MenuBuilder.swift"
    ]
    
    for file in requiredFiles {
        runner.run("\(file) exists") {
            fm.fileExists(atPath: "\(basePath)/\(file)")
        }
    }
    
    // Executable exists
    runner.run("mdview executable exists") {
        fm.fileExists(atPath: "\(basePath)/mdview")
    }
    
    // Fixtures exist
    runner.run("Fixtures/test.md exists") {
        fm.fileExists(atPath: "\(basePath)/Fixtures/test.md")
    }

    runner.run("Fixtures/mermaid.md exists") {
        fm.fileExists(atPath: "\(basePath)/Fixtures/mermaid.md")
    }
    
    // Makefile exists
    runner.run("Makefile exists") {
        fm.fileExists(atPath: "\(basePath)/Makefile")
    }
    
    // README exists
    runner.run("README.md exists") {
        fm.fileExists(atPath: "\(basePath)/README.md")
    }
}

// MARK: - File content tests

func testFileContents(_ runner: TestRunner) {
    print("\n📄 File content tests")
    print(String(repeating: "-", count: 40))
    
    let basePath = FileManager.default.currentDirectoryPath
    
    // main.swift content
    runner.run("main.swift contains NSApplication") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/main.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSApplication") && content.contains("AppDelegate")
    }
    
    // AppDelegate.swift content
    runner.run("AppDelegate.swift contains required components") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/AppDelegate.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSApplicationDelegate") &&
               content.contains("NSWindow") &&
               content.contains("NativeMarkdownView") &&
               content.contains("FileHandler") &&
               content.contains("MenuBuilder")
    }

    // WebKit removed: no MarkdownView.swift and no WebKit imports
    runner.run("WebKit-related files are removed") {
        let fm = FileManager.default
        let removedFile = !fm.fileExists(atPath: "\(basePath)/Sources/MarkdownView.swift")
        let appDelegate = (try? String(contentsOfFile: "\(basePath)/Sources/AppDelegate.swift", encoding: .utf8)) ?? ""
        let native = (try? String(contentsOfFile: "\(basePath)/Sources/NativeMarkdownView.swift", encoding: .utf8)) ?? ""
        let menu = (try? String(contentsOfFile: "\(basePath)/Sources/MenuBuilder.swift", encoding: .utf8)) ?? ""
        let main = (try? String(contentsOfFile: "\(basePath)/Sources/main.swift", encoding: .utf8)) ?? ""
        let package = (try? String(contentsOfFile: "\(basePath)/Package.swift", encoding: .utf8)) ?? ""
        return removedFile &&
            !appDelegate.contains("WebKit") &&
            !native.contains("WebKit") &&
            !menu.contains("WebKit") &&
            !main.contains("WebKit") &&
            !package.contains("WebKit")
    }
    
    // NativeMarkdownView.swift content
    runner.run("NativeMarkdownView.swift uses NSTextView native rendering") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/NativeMarkdownView.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSTextView") && content.contains("NSAttributedString") && content.contains("NativeCodeHighlighter")
    }
    
    // FileHandler.swift content
    runner.run("FileHandler.swift includes file watching") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/FileHandler.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("DispatchSource") && content.contains("readFile")
    }
    
    // MenuBuilder.swift content
    runner.run("MenuBuilder.swift builds menus") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Sources/MenuBuilder.swift", encoding: .utf8) else {
            return false
        }
        return content.contains("NSMenu") && content.contains("buildMainMenu")
    }
    
    // Fixtures/test.md is valid Markdown
    runner.run("Fixtures/test.md contains valid Markdown syntax") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Fixtures/test.md", encoding: .utf8) else {
            return false
        }
        return content.contains("# ") &&   // headings
               content.contains("```") &&  // code fences
               content.contains("- ") &&   // lists
               content.contains("|")       // tables
    }

    runner.run("Fixtures/mermaid.md contains a mermaid fenced code block") {
        guard let content = try? String(contentsOfFile: "\(basePath)/Fixtures/mermaid.md", encoding: .utf8) else {
            return false
        }
        return content.contains("```mermaid") && content.contains("flowchart")
    }
}

// MARK: - Compilation/runtime tests

private func extractMermaidCodes(from markdown: String) -> [String] {
    // Extract all ```mermaid ...``` blocks and return their inner text (trim to match MermaidRenderer behavior).
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    var inFence = false
    var lang = ""
    var buf: [String] = []
    var out: [String] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            if inFence {
                if lang == "mermaid" {
                    out.append(buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                }
                inFence = false
                lang = ""
                buf.removeAll(keepingCapacity: true)
            } else {
                inFence = true
                lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                buf.removeAll(keepingCapacity: true)
            }
            continue
        }
        if inFence { buf.append(line) }
    }
    return out
}

private func base64URLDecode(_ s: String) -> Data? {
    var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let rem = b64.count % 4
    if rem != 0 {
        b64.append(String(repeating: "=", count: 4 - rem))
    }
    return Data(base64Encoded: b64)
}

private func base64URLDecodeToUTF8String(_ s: String) -> String? {
    guard let data = base64URLDecode(s) else { return nil }
    return String(data: data, encoding: .utf8)
}

func testCompilation(_ runner: TestRunner) {
    print("\n🔨 Compilation/runtime tests")
    print(String(repeating: "-", count: 40))
    
    // mdview is a valid Mach-O executable
    runner.run("mdview is a valid Mach-O executable") {
        let basePath = FileManager.default.currentDirectoryPath
        // mdview at repo root may be a symlink (to .build product); `file` needs -L to follow it.
        let result = runProcess("/usr/bin/file", ["-L", "\(basePath)/mdview"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("Mach-O") && result.output.contains("executable")
    }
    
    // Linked frameworks
    runner.run("mdview links AppKit framework") {
        let basePath = FileManager.default.currentDirectoryPath
        let result = runProcess("/usr/bin/otool", ["-L", "\(basePath)/mdview"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("AppKit")
    }
    
    runner.run("mdview should not link WebKit framework") {
        let basePath = FileManager.default.currentDirectoryPath
        let result = runProcess("/usr/bin/otool", ["-L", "\(basePath)/mdview"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && !result.output.contains("WebKit")
    }

    // In some automation environments (e.g. no GUI session/WindowServer or platform limitations),
    // AppKit apps may be SIGKILL'ed by the system (terminationStatus=9).
    // Skipping by default can hide local regressions, so we FAIL by default and only allow skipping via env var.
    let basePath = FileManager.default.currentDirectoryPath
    let allowSkipSubprocess = (ProcessInfo.processInfo.environment["MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS"] == "1")

    let probe = runProcess("\(basePath)/mdview", ["--help"], timeoutSeconds: 2.0)
    let canRunMdview = !probe.didTimeout && probe.terminationStatus == 0
    if !canRunMdview {
        if allowSkipSubprocess {
            print("  ⚠️ Skipping mdview subprocess tests (MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS=1): status=\(probe.terminationStatus) timeout=\(probe.didTimeout)")
            return
        } else {
            runner.run(
                "mdview subprocess can start (--help)",
                test: { false },
                message: "status=\(probe.terminationStatus) timeout=\(probe.didTimeout)"
            )
            return
        }
    }
    
    // GUI smoke test: ensure launching from CLI can create a window and exit automatically
    runner.run("mdview --smoke-test shows GUI and exits") {
        let result = runProcess("\(basePath)/mdview", ["--smoke-test"], timeoutSeconds: 5.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("SMOKE_OK")
    }

    // In background/subprocess environments, forcing activation can be killed; provide --no-activate as a safer path.
    runner.run("mdview --no-activate --smoke-test exits cleanly") {
        let result = runProcess("\(basePath)/mdview", ["--no-activate", "--smoke-test"], timeoutSeconds: 5.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("SMOKE_OK")
    }

    // GUI screenshot test: ensure it can output a PNG
    runner.run("mdview --screenshot outputs PNG and exits") {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let out = tmpDir.appendingPathComponent("mdview-screenshot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: out) }

        let result = runProcess(
            "\(basePath)/mdview",
            ["--screenshot", out.path, "--screenshot-delay", "0.2", "\(basePath)/Fixtures/test.md"],
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

    // Blockquote blank lines / paragraph spacing: deterministic regression via plain-text output
    runner.run("mdview --render-text: a blank `>` line in blockquote creates a paragraph break") {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tmpFile = tmpDir.appendingPathComponent("mdview-blockquote-spacing-\(UUID().uuidString).md")
        let markdown = """
        > line1
        > line2
        >
        > — author
        """

        do {
            try markdown.write(to: tmpFile, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = runProcess("\(basePath)/mdview", ["--render-text", tmpFile.path], timeoutSeconds: 2.0)
        let output = result.output

        // Expect:
        // - line1 and line2 separated by a single newline (line break within the same paragraph)
        // - line2 and author separated by a blank line (paragraph break)
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("line1\nline2\n\n— author") &&
               !output.contains("line1\n\nline2")
    }

    // Screenshot + scroll-to: ensure it can reliably capture non-first-screen content (table/quote etc.)
    runner.run("mdview --screenshot-scroll-to scrolls and outputs PNG") {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let out = tmpDir.appendingPathComponent("mdview-screenshot-scroll-to-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: out) }

        let fixture = "\(basePath)/Fixtures/table_width.md"
        let result = runProcess(
            "\(basePath)/mdview",
            ["--no-activate", "--screenshot", out.path, "--screenshot-delay", "0.2", "--screenshot-scroll-to", "SCROLLTARGETTABLE", fixture],
            timeoutSeconds: 10.0
        )
        guard !result.didTimeout, result.terminationStatus == 0, result.output.contains("SCREENSHOT_OK") else { return false }

        guard FileManager.default.fileExists(atPath: out.path) else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: out.path),
              let size = attrs[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 10_000
    }

    // CLI help: should not launch GUI and should exit quickly
    runner.run("mdview --help exits and prints usage") {
        let result = runProcess("\(basePath)/mdview", ["--help"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("Usage:") && result.output.contains("--pipeline")
    }

    // Native dump: ensure table parsing is triggered (avoid "table disappears" regression)
    runner.run("mdview --dump parses the table in Fixtures/test.md") {
        let result = runProcess("\(basePath)/mdview", ["--dump", "\(basePath)/Fixtures/test.md"], timeoutSeconds: 2.0)
        let output = result.output
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("[[TABLE]]") &&
               output.contains("Feature") &&
               output.contains("Status") &&
               output.contains("Notes")
    }

    runner.run("mdview --dump detects image syntax") {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tmpFile = tmpDir.appendingPathComponent("mdview-native-dump-image-test.md")
        let markdown = "![icon](./nonexistent.png)\n"
        
        do {
            try markdown.write(to: tmpFile, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        
        let basePath = FileManager.default.currentDirectoryPath
        let result = runProcess("\(basePath)/mdview", ["--dump", tmpFile.path], timeoutSeconds: 2.0)
        let output = result.output
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("[[IMAGE]]") &&
               output.contains("icon") &&
               output.contains("./nonexistent.png")
    }

    // Mermaid.ink encoder: validate URL shape without network (produced by mdview --dump)
    runner.run("mdview --dump prints Mermaid diagram URL (mermaid.ink /svg/<base64url(text)>)") {
        let result = runProcess("\(basePath)/mdview", ["--dump", "\(basePath)/Fixtures/test.md"], timeoutSeconds: 2.0)
        guard !result.didTimeout, result.terminationStatus == 0 else { return false }

        // Expect a line like: [[MERMAID_URL]] https://mermaid.ink/svg/<base64url>?...
        guard let line = result.output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first(where: { $0.hasPrefix("[[MERMAID_URL]] ") }) else {
            return false
        }
        let urlString = line.replacingOccurrences(of: "[[MERMAID_URL]] ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString) else { return false }
        guard url.host == "mermaid.ink" else { return false }
        guard url.path.hasPrefix("/svg/") else { return false }

        // base64url allows only [A-Za-z0-9_-] and should not contain '=' or whitespace.
        let payload = String(url.path.dropFirst("/svg/".count))
        guard !payload.isEmpty else { return false }
        guard !payload.contains("="), payload.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }

        // Only allow base64url characters.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return payload.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // Mermaid: deterministic checks without network:
    // 1) --render-text should include attachment object replacement char (U+FFFC)
    runner.run("mdview Mermaid fixture: --render-text contains attachment placeholder (U+FFFC)") {
        let fixture = "\(basePath)/Fixtures/mermaid.md"
        let result = runProcess("\(basePath)/mdview", ["--render-text", fixture], timeoutSeconds: 2.0)
        let output = result.output
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("flowchart TD") &&
               output.contains("\u{FFFC}")
    }

    // 2) [[MERMAID_URL]] from --dump can round-trip back to the original code (base64url decode)
    runner.run("mdview Mermaid fixture: mermaid.ink URL round-trips back to original code") {
        let fixturePath = "\(basePath)/Fixtures/mermaid.md"
        guard let fixtureContent = try? String(contentsOfFile: fixturePath, encoding: .utf8) else { return false }
        let expectedCodes = extractMermaidCodes(from: fixtureContent)
        guard !expectedCodes.isEmpty else { return false }

        let dump = runProcess("\(basePath)/mdview", ["--dump", fixturePath], timeoutSeconds: 2.0)
        guard !dump.didTimeout, dump.terminationStatus == 0 else { return false }

        let lines = dump.output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let urlLines = lines.filter { $0.hasPrefix("[[MERMAID_URL]] ") }
        guard urlLines.count == expectedCodes.count else { return false }

        for (idx, line) in urlLines.enumerated() {
            let urlString = line.replacingOccurrences(of: "[[MERMAID_URL]] ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: urlString), url.host == "mermaid.ink" else { return false }
            guard url.path.hasPrefix("/svg/") else { return false }

            let payload = String(url.path.dropFirst("/svg/".count))
            guard let decoded = base64URLDecodeToUTF8String(payload) else { return false }
            
            // Remove MermaidRenderer auto-injected init directive (%%{init: ...}%%) before comparing.
            let decodedTrimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedCode = expectedCodes[idx]
            
            // If decoded includes an init directive, strip it before comparing.
            let codeWithoutInit: String
            if decodedTrimmed.hasPrefix("%%{init:") {
                // Find the first "}%%" then take the content after it.
                if let range = decodedTrimmed.range(of: "}%%") {
                    var afterInit = String(decodedTrimmed[range.upperBound...])
                    // Remove leading newlines
                    while afterInit.hasPrefix("\n") {
                        afterInit.removeFirst()
                    }
                    codeWithoutInit = afterInit.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    codeWithoutInit = decodedTrimmed
                }
            } else {
                codeWithoutInit = decodedTrimmed
            }
            
            if codeWithoutInit != expectedCode {
                return false
            }
        }

        return true
    }
    
    // Native render text: ensure content after a fenced code block is still rendered (regression: missing content after a code block)
    runner.run("mdview --render-text does not drop content after a fenced code block") {
        let result = runProcess("\(basePath)/mdview", ["--render-text", "\(basePath)/Fixtures/test.md"], timeoutSeconds: 2.0)
        let output = result.output
        
        // After the code block, Fixtures/test.md should include "Table example", "Blockquote", "Task list"
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("Table example") &&
               output.contains("Blockquote") &&
               output.contains("Task list")
    }

    // AST pipeline: should run and fall back on table/task/image (output should be unchanged)
    runner.run("mdview --pipeline=ast --render-text outputs successfully") {
        let result = runProcess("\(basePath)/mdview", ["--pipeline=ast", "--render-text", "\(basePath)/Fixtures/test.md"], timeoutSeconds: 2.0)
        let output = result.output
        return !result.didTimeout && result.terminationStatus == 0 &&
               output.contains("Table example") &&
               output.contains("Blockquote") &&
               output.contains("Task list")
    }

    // Native skeleton: width skeleton regression check (avoid per-character wrapping)
    runner.run("mdview --skeleton-check returns SKELETON_OK") {
        let result = runProcess("\(basePath)/mdview", ["--skeleton-check"], timeoutSeconds: 2.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("SKELETON_OK")
    }

    // Highlightr: verify SPM resource bundle + JSCore works
    runner.run("mdview --highlightr-check returns HIGHLIGHTR_OK") {
        let result = runProcess("\(basePath)/mdview", ["--highlightr-check"], timeoutSeconds: 4.0)
        return !result.didTimeout && result.terminationStatus == 0 && result.output.contains("HIGHLIGHTR_OK")
    }
}

// MARK: - FileHandler unit tests

func testFileHandler(_ runner: TestRunner) {
    print("\n📂 FileHandler unit tests")
    print(String(repeating: "-", count: 40))
    
    let basePath = FileManager.default.currentDirectoryPath
    let testFilePath = "\(basePath)/Fixtures/test.md"
    
    // File read logic
    runner.run("Read an existing file") {
        let url = URL(fileURLWithPath: testFilePath)
        do {
            let _ = try String(contentsOf: url, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
    
    runner.run("Reading a missing file throws") {
        let url = URL(fileURLWithPath: "/nonexistent/file.md")
        do {
            let _ = try String(contentsOf: url, encoding: .utf8)
            return false  // should not succeed
        } catch {
            return true   // should throw
        }
    }
    
    runner.run("Detect .md extension") {
        let path = "test.md"
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "md"
    }
    
    runner.run("Detect .markdown extension") {
        let path = "readme.markdown"
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "markdown"
    }
    
    runner.run("Resolve relative path") {
        let relativePath = "test.md"
        let absolutePath: String
        if relativePath.hasPrefix("/") {
            absolutePath = relativePath
        } else {
            absolutePath = FileManager.default.currentDirectoryPath + "/" + relativePath
        }
        return absolutePath.hasPrefix("/") && absolutePath.hasSuffix("test.md")
    }
    
    runner.run("Resolve absolute path") {
        let absoluteInput = "/Users/test/file.md"
        let result: String
        if absoluteInput.hasPrefix("/") {
            result = absoluteInput
        } else {
            result = FileManager.default.currentDirectoryPath + "/" + absoluteInput
        }
        return result == "/Users/test/file.md"
    }
    
    runner.run("Get file name") {
        let path = "/path/to/file.md"
        let filename = (path as NSString).lastPathComponent
        return filename == "file.md"
    }
    
    runner.run("Get directory path") {
        let path = "/path/to/file.md"
        let directory = (path as NSString).deletingLastPathComponent
        return directory == "/path/to"
    }
}

// MARK: - Makefile tests

func testMakefile(_ runner: TestRunner) {
    print("\n⚙️ Makefile tests")
    print(String(repeating: "-", count: 40))
    
    let basePath = FileManager.default.currentDirectoryPath
    
    guard let makefileContent = try? String(contentsOfFile: "\(basePath)/Makefile", encoding: .utf8) else {
        runner.run("Makefile is readable") { false }
        return
    }
    
    runner.run("Makefile defines APP_NAME") {
        makefileContent.contains("APP_NAME")
    }
    
    runner.run("Makefile defines SOURCES") {
        makefileContent.contains("SOURCES")
    }
    
    runner.run("Makefile defines debug target") {
        makefileContent.contains("debug:")
    }
    
    runner.run("Makefile defines release target") {
        makefileContent.contains("release:")
    }
    
    runner.run("Makefile defines clean target") {
        makefileContent.contains("clean:")
    }
    
    runner.run("Makefile links AppKit framework") {
        makefileContent.contains("-framework AppKit")
    }
    
    runner.run("Makefile should not link WebKit framework") {
        !makefileContent.contains("-framework WebKit")
    }
}

// MARK: - Main

print("""

╔══════════════════════════════════════════════════╗
║     macOS Markdown Viewer - Test Suite           ║
╚══════════════════════════════════════════════════╝
""")

let runner = TestRunner()

testFileSystem(runner)
testFileContents(runner)
testCompilation(runner)
testFileHandler(runner)
testMakefile(runner)

runner.printSummary()

// Return exit code
exit(runner.failed > 0 ? 1 : 0)
