# mdview (`mdview`) — TODO (progress tracking, for LLM)

## Current status
- **Renderer**: native-only (`NSTextView`)
- **Input**: local `.md`/`.markdown` (drag & drop; auto-reload on file changes)
- **Automation**: supports `--smoke-test`, `--screenshot*`, `--dump`, `--render-text`, `--skeleton-check`, `--highlightr-check`

## Invariants (avoid regressions)
- Native rendering **must not wrap per character**: text container width must track scrollView visible width, and must force reflow.
- In background job/subprocess environments, **do not force activate**: use `--no-activate` when needed.
- All build/test/subprocess flows must have **timeout + kill**.

## TODO
- [x] Support multiple `.md/.markdown` CLI args (multi-window) and multi-select in `Open…` (2025-12-15)
- [x] Add theme: `--theme=system|light|dark` + menu switching (2025-12-15)
- [x] Set Dock icon after launch (avoid default `exec` icon when not running as a bundle) (2025-12-15)

(No pending TODO items at the moment)

## Maintenance notes (not TODO)
- If you add/change CLI flags: update `--help` in `Sources/main.swift` and coverage in `Tests/test_runner.swift`
- If you change layout (quote/table/code block): add at least one regression test via `--render-text` and `--screenshot-scroll-to`

## Quick commands
```bash
make debug
make test
./mdview Fixtures/test.md

# Visual verification (PNG)
./mdview --no-activate --screenshot .tmp/mdview.png --screenshot-delay 0.2 Fixtures/test.md
```
