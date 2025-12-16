## unused-code-removal tracker

### 目標
- 移除 repo 內「已確認無引用」的代碼（刪檔/刪未使用宣告）。
- 確保 `make debug`、`make test` 全數通過。

### 盤點結論（2025-12-16）
- `IncrementalSyntaxHighlighter` 僅出現在：
  - `Sources/IncrementalSyntaxHighlighter.swift`（定義）
  - `Makefile`（SOURCES 硬編清單）
  - `Tests/test_runner.swift`（requiredFiles 硬編清單）
  - **未發現任何實際使用點**。
- `FileHandler` 內下列 methods 目前僅有定義、未發現呼叫點：
  - `fileExists(at:)`
  - `isMarkdownFile(at:)`
  - `getFileName(from:)`
  - `getFileDirectory(from:)`
- `FileHandler.resolveAbsolutePath(_:)` 有使用點（`Sources/AppDelegate.swift`）。

### 已完成
- [x] 更新 `Makefile` 移除 `Sources/IncrementalSyntaxHighlighter.swift`
- [x] 更新 `Tests/test_runner.swift` 移除 `Sources/IncrementalSyntaxHighlighter.swift`

### 進行中
- [x] `git rm Sources/IncrementalSyntaxHighlighter.swift`
- [x] 移除 `Sources/FileHandler.swift` 內未使用 helper methods（`fileExists/isMarkdownFile/getFileName/getFileDirectory`）
- [x] 跑 `make debug` / `make test` + smoke（`make debug`、`make test`、`./mdview --help`、`./mdview --no-activate --smoke-test` 皆通過）
- [ ] commit

### 驗證結果摘要
- `make debug`: ✅
- `make test`: ✅（57 passed, 0 failed）
- `./mdview --help`: ✅
- `./mdview --no-activate --smoke-test`: ✅（輸出 `SMOKE_OK`）
