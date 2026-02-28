# mdview

`mdview` is a native macOS Markdown reader built with Swift and AppKit. It focuses on fast local-file viewing, predictable automation hooks, and a renderer that stays close to macOS text-system behavior instead of embedding a browser view.

## What stands out

- Native `NSTextView` rendering with selectable text, system typography, dark mode, zoom controls, and standard macOS menus.
- File-oriented workflow: open `.md`, `.markdown`, and `.txt` files from the CLI, Finder, drag and drop, or an already-running app instance.
- Auto-reload on file changes using `DispatchSource`, so edits appear without reopening the document.
- Multiple document windows with duplicate-open detection: opening an already-visible file reloads and focuses the existing window.
- Read-only ergonomics: copy selected text, copy full document content, copy the current file path, search with the native find UI, and switch themes at runtime.
- Markdown coverage for headings, paragraphs, links, emphasis, inline code, fenced code blocks, syntax highlighting, lists, task lists, blockquotes, horizontal rules, tables, images, and Mermaid diagrams.
- Automation-first test hooks: deterministic text rendering, parser dumps, skeleton layout checks, smoke tests, and screenshot capture with scroll targeting.

## Installation

Requirements:

- macOS 10.15 or newer
- Swift 5.9 or newer
- Xcode command line tools

Build the debug binary:

```bash
make debug
```

Build an optimized release binary:

```bash
make release
```

The build creates `./mdview` as a symlink to the SwiftPM product under `.build/`.

## Usage

Open one file:

```bash
./mdview README.md
```

Open multiple files:

```bash
./mdview Fixtures/test.md Fixtures/table_width.md
```

Keep the process attached to the terminal:

```bash
./mdview --wait README.md
```

Launch without activating the app, useful for background jobs and automation:

```bash
./mdview --no-activate README.md
```

Force a theme:

```bash
./mdview --theme=dark README.md
```

Try the AST pipeline:

```bash
./mdview --pipeline=ast README.md
```

## CLI Reference

```text
mdview [options] [file.md ...]

Options:
  --help, -h
  --wait, --debug
  --no-activate
  --theme=system|light|dark
  --pipeline=regex|ast
  --ast
  --smoke-test
  --screenshot <out.png>
  --screenshot=<out.png>
  --screenshot-full
  --screenshot-scroll-to <text>
  --screenshot-scroll-y <number>
  --screenshot-delay <sec>
  --screenshot-delay=<sec>

Debug and test modes:
  --dump <file.md>
  --render-text <file.md>
  --skeleton-check
  --highlightr-check
```

Default launch behavior detaches from the terminal, similar to `open`. Use `--wait` or `--debug` when you want the process to remain attached.

## Rendering Notes

`mdview` currently keeps two Markdown pipelines:

- `regex`: the default production path. It includes the widest local feature coverage.
- `ast`: an incremental `swift-markdown` pipeline. It falls back to the default renderer for tables, task lists, and images so unsupported syntax does not disappear.

Mermaid code fences are rendered as the original fenced code block plus a diagram inserted below it. Diagram images are loaded through `mermaid.ink` in the background; PNG is preferred where it gives better AppKit fidelity.

Remote images are also loaded asynchronously. Rendering never blocks on network requests.

## Development

Common commands:

```bash
make debug
make test
make smoke
make clean
```

`make test` builds the app, ad-hoc signs the SwiftPM product, and runs the Swift test runner. The tests cover repository structure, renderer regressions, CLI behavior, screenshot output contracts, Mermaid URL encoding, Highlightr setup, file reading, file watching, and Makefile safeguards.

Automation output contracts:

- Screenshot success: `SCREENSHOT_OK <path>` with exit code `0`
- Screenshot failure: `SCREENSHOT_FAIL <path>` with exit code `1`
- Screenshot timeout: `SCREENSHOT_TIMEOUT <path>` with exit code `2`
- Scroll target missing: `SCREENSHOT_SCROLL_TO_NOT_FOUND <text> <path>` with exit code `1`
- Smoke success: `SMOKE_OK` with exit code `0`
- Smoke failure: `SMOKE_FAIL` with exit code `1`

## Architecture

Recommended reading order:

- `Sources/main.swift`: CLI parsing, detach behavior, validation, and test-mode entry points.
- `Sources/AppDelegate.swift`: app lifecycle, single-instance handoff, windows, screenshot and smoke flows.
- `Sources/MarkdownWindowController.swift`: one document window, renderer ownership, drag and drop, file watching.
- `Sources/NativeMarkdownView.swift`: native Markdown rendering, layout, parsing, screenshots, and scroll targeting.
- `Sources/ASTMarkdownRenderer.swift`: incremental `swift-markdown` renderer.
- `Sources/RemoteImageAttachment.swift`: non-blocking remote image loading and Mermaid PNG fallback behavior.
- `Sources/FileHandler.swift`: file reading and file change watching.
- `Sources/MenuBuilder.swift`: macOS menu structure and shortcuts.
- `Tests/test_runner.swift`: regression test entry point.

Key invariants:

- Text container width must track the scroll view's visible width to prevent per-character wrapping.
- Automation paths must exit on their own; tests and screenshot modes should never depend on manual window closure.
- Horizontal rules are rendered as a long left-aligned clipped line in both the regex and AST pipelines.
- CLI debug and test modes run in the current process instead of handing off to an existing app instance.

## Troubleshooting

### `IMKCFRunLoopWakeUpReliable` or Mach port logs

These messages are usually macOS InputMethodKit or TextKit system logs emitted while the text input subsystem initializes. The project does not print those strings. They are generally harmless if text selection, copying, and input-method behavior work normally.

For cleaner automation logs, assert against `stdout` contracts and filter known noisy `stderr` strings when needed.

### GUI subprocess cannot run

By default, `make test` treats a non-runnable GUI subprocess as a failure. In a constrained environment where GUI subprocess execution is expected to fail, opt into the skip explicitly:

```bash
MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS=1 make test
```
