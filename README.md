# mdview（`mdviewer`）— LLM 專案入口

## 目的
macOS Markdown Reader（AppKit）。**只讀**：讀取本機 `.md`/`.markdown`，渲染到畫面，支援拖放與檔案變更自動 reload。

## 最常用指令
```bash
make debug
make test
make smoke

./mdviewer Fixtures/test.md
./mdviewer Fixtures/test.md Fixtures/table_width.md
./mdviewer --theme=dark Fixtures/test.md
./mdviewer --help
```

## CLI（以 `Sources/main.swift` 為準）
- **前景/背景啟動**：`--no-activate`（在 background job `&` / 子行程 / CI 內建議加，避免被系統終止）
- **主題（Theme）**：`--theme=system|light|dark`（預設 system；也可用選單 `檢視 → 主題` 切換）
- **Native pipeline**：`--native-pipeline=regex|ast`、`--native-ast`
- **GUI smoke**：`--smoke-test`（建立視窗後自動退出）
- **GUI screenshot（CI/LLM 視覺驗證）**：
  - `--screenshot <out.png>`、`--screenshot-delay <sec>`（預設 1.0）
  - `--screenshot-scroll-to <text>`（推薦：確保目標區塊一定在截圖範圍內）
  - `--screenshot-scroll-y <number>`
  - `--screenshot-full`（有高度上限；超出會失敗，請改用 scroll-to）
- **不啟動 GUI 的測試/除錯**：
  - `--native-dump <file.md>`（輸出可做字串比對的解析結果）
  - `--native-render-text <file.md>`（輸出渲染後純文字；測 deterministic regression）
  - `--native-skeleton-check`（寬度骨架回歸檢查：避免「每字換行」）
  - `--highlightr-check`（驗證 Highlightr / JSCore / resources 可用）

## 測試輸出協定（供 automation/LLM 判斷）
- **screenshot**：stdout 會印
  - `SCREENSHOT_OK <path>`（exit 0）
  - `SCREENSHOT_FAIL <path>`（exit 1）
  - `SCREENSHOT_TIMEOUT <path>`（exit 2）
  - `SCREENSHOT_SCROLL_TO_NOT_FOUND <text> <path>`（exit 1）
- **smoke**：stdout 會印 `SMOKE_OK`（exit 0）或 `SMOKE_FAIL`（exit 1）

## 重要不變式（回歸最常發生在這）
- **不能每字換行**：`NSTextContainer` 寬度必須跟著 `NSScrollView` 可視寬同步，且幾何變更時要強制 reflow（見 `NativeMarkdownView.syncTextContainerWidth()`）。
- **所有自動化路徑要有 timeout**：測試與 screenshot/smoke 都必須能自行退出（Makefile / 測試 runner 已採 timeout + kill）。

## 程式碼入口（優先閱讀順序）
- `Sources/main.swift`：CLI flags / 測試模式入口
- `Sources/AppDelegate.swift`：視窗、載檔、檔案監控、screenshot/smoke 流程
- `Sources/NativeMarkdownView.swift`：Native renderer（排版/寬度/截圖/scroll-to 關鍵）
- `Sources/ASTMarkdownRenderer.swift`：AST 管線（`swift-markdown`）
- `Sources/FileHandler.swift`：讀檔 + 檔案變更監控
- `Sources/MenuBuilder.swift`：選單/快捷鍵
- `Tests/test_runner.swift`：測試入口

## FAQ
### 為什麼執行後會看到 `IMKCFRunLoopWakeUpReliable` / `mach port` 的 error log？
這通常是 **macOS InputMethodKit / TextKit** 在初始化文字輸入子系統時輸出的系統 log（本專案內沒有印這段字串）。多數情況下 **不影響功能**，可以忽略。

若你需要讓自動化輸出更乾淨，可考慮：
- 在測試/CI 僅看 `stdout`（把 `stderr` 分流/過濾特定字串）
- 或改用 `.app bundle` 形式啟動（較符合 macOS 慣例，且也更容易有正式 Dock icon）

## 在「無法啟動 GUI 子行程」環境
預設 `make test` 會把「mdviewer 子行程不可執行」視為失敗（避免掩蓋回歸）。若你在特殊環境需要跳過，改用：

```bash
MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS=1 make test
```
