# mdview (`mdview`) — LLM project entry

## Purpose
macOS Markdown reader (AppKit). **Read-only**: reads local `.md`/`.markdown`, renders to a window, supports drag & drop and auto-reload on file changes.

## Most used commands
```bash
make debug
make test
make smoke

./mdview Fixtures/test.md
./mdview Fixtures/test.md Fixtures/table_width.md
./mdview --theme=dark Fixtures/test.md
./mdview --help
```

## CLI (source of truth: `Sources/main.swift`)
- **Foreground/background**: `--no-activate` (recommended for background jobs `&` / subprocesses / CI to avoid being killed by the system)
- **Theme**: `--theme=system|light|dark` (default: system; can also switch via menu `View → Theme`)
- **Markdown pipeline**：`--pipeline=regex|ast`、`--ast`
- **GUI smoke**: `--smoke-test` (create a window, then exit automatically)
- **Mermaid (default)**: for ` ```mermaid ` code blocks, the renderer **keeps the code block** and inserts a diagram below (via `mermaid.ink`; prefers PNG for fidelity; requires network; loads non-blockingly)
- **GUI screenshot (CI/LLM visual verification)**:
  - `--screenshot <out.png>`, `--screenshot-delay <sec>` (default: 1.0)
  - `--screenshot-scroll-to <text>` (recommended: ensure the target block is within the screenshot)
  - `--screenshot-scroll-y <number>`
  - `--screenshot-full` (has a height limit; if it fails, use scroll-to)
- **No-GUI debug/tests**:
  - `--dump <file.md>` (print parse output suitable for string comparisons)
  - `--render-text <file.md>` (print rendered plain text; deterministic regression)
  - `--skeleton-check` (width skeleton regression check: avoid per-character wrapping)
  - `--highlightr-check` (verify Highlightr / JSCore / resources)

## Test output contract (for automation/LLM)
- **screenshot**: stdout prints
  - `SCREENSHOT_OK <path>` (exit 0)
  - `SCREENSHOT_FAIL <path>` (exit 1)
  - `SCREENSHOT_TIMEOUT <path>` (exit 2)
  - `SCREENSHOT_SCROLL_TO_NOT_FOUND <text> <path>` (exit 1)
- **smoke**: stdout prints `SMOKE_OK` (exit 0) or `SMOKE_FAIL` (exit 1)

## Important invariants (common regression sources)
- **No per-character wrapping**: `NSTextContainer` width must track `NSScrollView` visible width, and geometry changes must force reflow (see `NativeMarkdownView.syncTextContainerWidth()`).
- **All automation paths must have timeouts**: tests and screenshot/smoke must exit on their own (Makefile / test runner use timeout + kill).

## Code entry points (recommended reading order)
- `Sources/main.swift`: CLI flags / test-mode entry points
- `Sources/AppDelegate.swift`: windows, file loading, file watching, screenshot/smoke flows
- `Sources/NativeMarkdownView.swift`: native renderer (layout/width/screenshot/scroll-to are key)
- `Sources/ASTMarkdownRenderer.swift`: AST pipeline (`swift-markdown`)
- `Sources/FileHandler.swift`: file reading + file change watching
- `Sources/MenuBuilder.swift`: menus / shortcuts
- `Tests/test_runner.swift`: test entry point

## FAQ
### Why do I see `IMKCFRunLoopWakeUpReliable` / `mach port` error logs?
This is usually a **macOS InputMethodKit (IMK) / TextKit** system log emitted while initializing the text input subsystem (this project does not print that string). The message `error messaging the mach port for IMKCFRunLoopWakeUpReliable` generally means IMK attempted to wake a run loop / communicate via a Mach port and the port was unavailable. In most cases it **does not affect functionality** and can be ignored.

Why it shows up here:
- `mdview` renders with `NSTextView` (read-only, but still part of the text input system), so IMK may be initialized when the window/text system becomes active.

What to do:
- If IME composition (e.g. Zhuyin/Pinyin candidate window) works normally, treat it as benign noise.
- If you need clean automation logs, prefer checking `stdout` only (or filter known-noisy `stderr` strings).
- Launching as a `.app bundle` can reduce the likelihood (more macOS-native launch context).

References (similar reports in other projects):
- [electron/electron#45002](https://github.com/electron/electron/issues/45002)
- [wezterm/wezterm#7249](https://github.com/wezterm/wezterm/issues/7249)

## In environments where the GUI subprocess cannot run
By default, `make test` treats "mdview subprocess cannot execute" as a failure (to avoid hiding regressions). If you must skip in a special environment, use:

```bash
MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS=1 make test
```
