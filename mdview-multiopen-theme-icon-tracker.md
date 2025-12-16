# mdview tracker：multi-open / themes / app icon / native flags

Date: 2025-12-15

## Goals
- Allow multiple `.md/.markdown` CLI args to open multiple files/windows
- Add themes: system/light/dark (switchable via CLI and menu)
- After launch, Dock icon is no longer the default `exec` icon
- Clarify and tidy up historical native/webkit naming/flags (keep compatibility, make the interface more intuitive)

## Investigation notes
### 1) `IMKCFRunLoopWakeUpReliable` message
Observed logs like:

- `error messaging the mach port for IMKCFRunLoopWakeUpReliable`

Preliminary conclusion:
- **Not printed by this project** (repo search for `IMKCFRunLoopWakeUpReliable` / `InputMethodKit` yields no hits).
- Very likely from **macOS InputMethodKit / TextKit**: initializing `NSTextView` triggers the text input subsystem; in some contexts it emits these logs (usually harmless).
- Mitigations:
  - Document as FAQ (safe to ignore if functionality is OK).
  - For cleaner logs: split stdout/stderr in the test runner and filter specific strings; or launch as a `.app bundle` to reduce likelihood.

### 2) Current CLI / renderer status
- The project is **native-only** (WebKit removed).
- CLI **no longer provides `--native`**; the pipeline is expressed via `--pipeline` / `--ast` (single coherent interface).

### 3) Note: AppKit `openFile` events vs argv
- In some launch paths, AppKit may treat "non-option argv" as `application(_:openFile:)` events.\n  Example: the `<out.png>` in `--screenshot <out.png>` may be misinterpreted as a document to open, making screenshot tests flaky.\n- Mitigation: only accept `.md/.markdown` in `openFile`; in screenshot mode, only open the first Markdown file as the target.

## Change list (to be completed)
- [x] CLI: support multiple file args → multi-window (`AppDelegate` + `MarkdownWindowController`)
- [x] Menu: multi-select in Open… (`NSOpenPanel.allowsMultipleSelection = true`)
- [x] Theme: `--theme=system|light|dark` + menu switching + rerender (`MarkdownRenderable.rerender()`)
- [x] Icon: set `NSApp.applicationIconImage` after launch (avoid exec icon; currently a simple generated "MD" icon)
- [x] Docs: update README/todo + FAQ (IMK log)
- [ ] Tests: update and run `make test`

## Acceptance criteria
- CLI: `./mdview a.md b.md c.md` opens multiple windows
- Theme: switching updates code highlighting and background/text colors consistently
- Dock icon: shows mdview icon (not exec)
- `make test` passes

## Follow-up notes (2025-12-15)
- List indentation tuned to be closer to macOS Notes: prefixes also indent, and tab stops + hanging indents align text.
- `Fixtures/test.md` expanded: added H1/H2/H3, image syntax, bullet/ordered lists, Mermaid samples.
- Mermaid support: for ` ```mermaid ` code blocks, keep the original code and insert a diagram below (via `mermaid.ink`; requires network; non-blocking load).
