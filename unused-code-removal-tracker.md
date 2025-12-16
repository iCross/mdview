## unused-code-removal tracker

### Goal
- Remove code that is confirmed to have no references in the repo (delete files / remove unused declarations).
- Ensure `make debug` and `make test` both pass.

### Inventory summary (2025-12-16)
- `IncrementalSyntaxHighlighter` appeared only in:
  - `Sources/IncrementalSyntaxHighlighter.swift` (definition)
  - `Makefile` (hard-coded SOURCES list)
  - `Tests/test_runner.swift` (hard-coded requiredFiles list)
  - **No actual usage sites were found**.
- In `FileHandler`, the following methods were defined but had no call sites:
  - `fileExists(at:)`
  - `isMarkdownFile(at:)`
  - `getFileName(from:)`
  - `getFileDirectory(from:)`
- `FileHandler.resolveAbsolutePath(_:)` had usage (`Sources/AppDelegate.swift`).

### Completed
- [x] Updated `Makefile` to remove `Sources/IncrementalSyntaxHighlighter.swift`
- [x] Updated `Tests/test_runner.swift` to remove `Sources/IncrementalSyntaxHighlighter.swift`

### In progress
- [x] `git rm Sources/IncrementalSyntaxHighlighter.swift`
- [x] Removed unused helper methods in `Sources/FileHandler.swift` (`fileExists/isMarkdownFile/getFileName/getFileDirectory`)
- [x] Ran `make debug` / `make test` + smoke (`make debug`, `make test`, `./mdview --help`, `./mdview --no-activate --smoke-test` all passed)
- [x] Commit (`391e71b3d04697af6ae68da143e3be05bc014f44`)

### Verification summary
- `make debug`: ✅
- `make test`: ✅ (57 passed, 0 failed)
- `./mdview --help`: ✅
- `./mdview --no-activate --smoke-test`: ✅ (prints `SMOKE_OK`)
