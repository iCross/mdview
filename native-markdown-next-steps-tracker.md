# markdown_swift 下一步計劃 tracker（Native / AST / Highlight）

更新日期：2025-12-14

## 目標
- 以現有 **純 Reader** 為核心（`NSTextView` 非編輯），把 Native renderer 做到「寬度跟視窗、排版一致、可維護的 Markdown 管線、可升級的語法高亮」。

## 參考 repo（已在本 repo 根目錄 clone；皆在 `.gitignore`）
- `Highlightr/`
- `MarkdownToAttributedString/`
- `MarkdownAttributedString/`
- `STTextView/`（GPL/commercial：僅觀察，不搬碼）

## 已整理的重點
- **Highlightr**
  - `Highlightr.highlight(_:as:)`：render-time 把 code 轉 `NSAttributedString`
  - `CodeAttributedString`（`NSTextStorage` 子類）：適合 incremental highlight（只改 attributes）
  - 依賴 `JavaScriptCore` 執行 highlight.js

- **MarkdownToAttributedString**
  - 走 `swift-markdown` AST（`Document(parsing:)` + visitor）→ `NSAttributedString`
  - 目前 repo 自述：不支援 tables/task lists/images（若採用需補齊或混合策略）

- **MarkdownAttributedString**
  - 主要處理 span（link/emphasis/code span），刻意不做 headers/lists 等 block

- **STTextView**
  - 可觀察 TextKit 2 / wrap / paragraphStyle / typingAttributes 的實務坑
  - 授權限制：不可複製程式碼進本 repo

## 方向決策（短期 / 中期）
- **Markdown 管線**
  - 短期：維持本 repo `NativeMarkdownParser`（已支援 table/image/task 等）
  - 中期：改走 **AST（`swift-markdown`）** 為基底，並補齊/混合處理 GFM table/task/image

- **語法高亮管線**
  - 短期：維持 regex（現況可用）
  - 中期：導入 **Highlightr**
    - Reader：先用於 code block render-time
    - 未來若做 Editor：改用 `CodeAttributedString` 做 incremental highlight（只更新 attributes）

## 進度
- [x] 階段A：參考 repo 已 clone + 筆記已補到 `README.md`
- [ ] 階段B：方向決策（Markdown/Highlight）文件化 + commit
- [ ] 階段C：Scroll/寬度骨架自動驗證與修正 + commit
- [ ] 階段D：Notes 風格 typography + commit
- [ ] 階段E：導入 AST 管線（SwiftPM + swift-markdown）+ commit
- [ ] 階段F：Highlightr（含 incremental highlight 路徑）+ commit
