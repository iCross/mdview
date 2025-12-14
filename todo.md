# macOS Markdown Viewer - 開發進度追蹤

## 階段 1：基礎架構建立
- [x] 建立專案結構 (Sources/, Resources/)
- [x] 建立 Makefile
- [x] 建立 todo.md 追蹤進度
- [x] 建立基本 macOS 視窗應用

## 階段 2：Markdown 渲染核心
- [x] 整合 WKWebView
- [x] 建立 HTML 渲染模板（內嵌於 MarkdownView.swift）
- [x] 整合 marked.js（透過 CDN）
- [x] 整合 highlight.js（透過 CDN）

## 階段 3：檔案處理與 UI 整合
- [x] 實作檔案讀取功能
- [x] 整合檔案拖放功能
- [x] 檔案變更自動重新載入

## 階段 4：進階功能
- [x] 選單列整合 (File, Edit, View, Window, Help)
- [x] 深色模式支援（自動跟隨系統設定）
- [x] 縮放功能（放大/縮小/實際大小）
- [x] 說明對話框

## 階段 5：打包與測試
- [x] 完善編譯腳本 (Makefile)
- [x] `make test` 先建置再執行測試（避免測到舊 binary）
- [x] 建立測試用 Markdown 檔案 (test.md)
- [x] 撰寫 README.md
- [x] Makefile 增加合理 timeout（build/run 避免卡住）

## 階段 6（選用）：輕量化渲染路線（NSTextView / NSAttributedString）
- [x] 新增原生渲染元件（`NativeMarkdownView.swift`），以 `NSTextView` 顯示內容（不使用 `WKWebView`）
- [x] 決定 Markdown 解析策略（簡化 parser + regex）
- [x] 實作 code block 語法高亮（regex 上色）
- [x] 原生表格支援（`NSTextTable` / `NSTextTableBlock`）
- [x] 原生圖片支援（`NSTextAttachment`；支援相對/絕對路徑，遠端圖若可載入則顯示）
- [x] AppDelegate 切換渲染器（WebKit / Native），並維持拖放、檔案監控、縮放等既有功能
- [x] CLI 參數：新增 `--help` / `--native-dump`（便於測試與除錯）
- [x] 修正 fenced code block 解析：避免結束 ``` 後誤把 closing fence 當成下一段 opening fence（修復 JS 區塊後內容不顯示）
- [x] 修正 Native code block/quote 寬度：`NSTextBlock.setContentWidth(100%, ...)` 避免每字換行
- [x] 修正 Native `NSTextView` 寬度同步：監聽 `NSClipView` bounds/frame 變化並強制 reflow
- [x] 測試補齊：新增 `--help` / `--native-dump` 相關測試（避免回歸）
- [x] 測試補齊：新增 `--native-render-text`（驗證 fenced code block 後續內容仍會被渲染）
- [x] 測試補齊：子行程統一 timeout/kill（避免測試卡死）
- [ ] 若完全移除 WebKit：更新 Makefile 的 FRAMEWORKS 與 Sources 清單（本次仍保留 WebKit 路線）

## 下一步計劃（準備重開新對話 / 以 `gh clone` 參考模板）

### 方向決策
- [x] 決定產品型態：**純 Reader（不可編輯）** vs **Reader + Editor（可編輯但強制一致 typography + 高亮）**（決定：純 Reader）
- [x] 決定 Markdown 管線：**短期維持自寫 parser（已支援 table/image/task）**；中期改走 **AST（swift-markdown）+ 自行補齊 GFM table/task/image**（或混合策略），以可維護性優先
- [x] 決定語法高亮管線：**短期維持 regex（現況可用）**；中期導入 **Highlightr**（render-time code block 高亮；若未來做 Editor，改用 `CodeAttributedString` 走 incremental highlight）

### 先抓下來看的 repo（用 `gh`）
> 目標：直接複製「NSTextView + NSScrollView + width 跟著視窗變」的穩定骨架，再疊 Markdown → NSAttributedString 與 incremental highlight。

```bash
gh repo clone chockenberry/MarkdownAttributedString
gh repo clone madebywindmill/MarkdownToAttributedString
gh repo clone raspu/Highlightr
gh repo clone krzyzanowskim/STTextView
```

- [x] 已 clone 參考 repo 到專案根目錄（`Highlightr/`、`MarkdownAttributedString/`、`MarkdownToAttributedString/`、`STTextView/`；皆在 `.gitignore`，不會進版控）
- [x] 已在 README 補上「參考 repo 筆記」摘要（Markdown AST / Highlightr / sizing / 授權注意事項）

### 優先驗證項目（比「功能加更多」更重要）
- [x] Scroll/寬度骨架：`NSTextView` 放進 `NSScrollView`，視窗縮放時**不會變成每字換行**、不會出現水平捲動（新增 `--native-skeleton-check` 自動驗證）
- [x] Notes 風格 typography：`textContainerInset` + `NSParagraphStyle`（lineHeight/spacing 策略）一致套用（Reader 模式為主；`NSTextContainer.lineFragmentPadding = 0`）
- [ ] Markdown→AttributedString：表格/圖片/連結/引用/code block 的 block-level 與 inline 樣式一致
- [ ] incremental highlight：只改 attributes、不改 characters；避免 `didProcessEditing` crash 類型問題

### AST 管線導入（中期）
- [x] 新增 `Package.swift` 並讓 Makefile 預設走 SwiftPM（`swift build`）以支援 `swift-markdown`
- [x] Native renderer 支援 `--native-pipeline=regex|ast`（`--native-ast`）切換；遇到 table/task/image 會 fallback 到既有 parser
- [ ] timeout 文化：所有 build/test/子行程都要有 timeout（避免卡住）

### GitHub 搜尋捷徑（新對話可直接貼這些關鍵字）
- [ ] `language:Swift NSTextView NSScrollView widthTracksTextView`
- [ ] `language:Swift Markdown NSAttributedString NSTextView`
- [ ] `language:Swift NSTextStorage syntax highlighting macOS`
- [ ] GitHub topic：`nstextview`（Swift 篩選）→ 以 stars / recently updated 挑模板

## 已完成功能
- 基本 Markdown 渲染
- GitHub Flavored Markdown 支援
- 程式碼語法高亮
- 深色/淺色模式自動切換
- 檔案拖放支援
- 檔案變更自動重新載入
- 完整選單系統
- 快捷鍵支援
- 縮放功能

## 使用方式
```bash
# 編譯
make debug

# 執行
./mdviewer test.md
```

## 完成日期
開始日期: 2024-12-14
完成日期: 2024-12-14
