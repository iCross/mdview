# markdown_swift（macOS Markdown Reader）— TODO（給 LLM）

## 專案目標 / 範圍
- **產品型態**：純 Reader（不提供編輯）
- **輸入**：讀取本機 `.md`（支援拖放、檔案變更自動 reload）
- **輸出**：渲染到畫面（支援縮放、深淺色跟隨系統）

## 目前架構（只留關鍵）
- **雙渲染路線**：
  - **WebKit（deprecated）**：`WKWebView`（marked.js / highlight.js 走 CDN）。仍可用但不建議；後續預計移除。
  - **Native**：`NSTextView`（自寫簡化 parser/regex 上色；支援 table / image / quote / fenced code block）
- **CLI（測試/除錯要用）**：`--help`、`--native-dump`、`--native-render-text`、`--native-pipeline=regex|ast`（或 `--native-ast`）、`--smoke-test`、`--screenshot`
- **不變式（避免回歸）**：
  - Native code block / quote **不能每字換行**（`NSTextBlock.setContentWidth(100%, ...)` 等處理必須保留）
  - `NSTextView` 寬度需跟著 scroll/視窗變化 **強制 reflow**（監聽 `NSClipView` bounds/frame 變更）
  - 所有 build/test/子行程都要有 **timeout + kill**（避免卡死）

## 仍待處理（唯一保留 TODO）
- [ ] **若未來決定完全移除 WebKit 路線**（已 deprecated）：更新 `Makefile` 的 `FRAMEWORKS` 與 `Sources` 清單、同步更新 `README.md` 的 renderer 說明與 CLI 描述，並刪除/移除 `Sources/MarkdownView.swift` 等相關 Swift 檔案的編譯引用（目前仍保留 WebKit）。

## 快速指令（只留最常用）
```bash
make debug
make test
./mdviewer test.md
```
