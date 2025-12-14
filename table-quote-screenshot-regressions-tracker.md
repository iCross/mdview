# table/quote/screenshot regressions tracker

日期：2025-12-14

## 目標
- 修掉 `test.md` 的兩個視覺回歸：
  - table 寬度：短內容表格不應縮成很窄、應至少撐滿容器；長內容仍可超出並水平捲動。
  - blockquote 空行/段落間距：`>` 空行應視為段落分隔；同一段落內多行引用不應被拆成多個 block 造成 paragraphSpacing 疊加。
- 補齊「截圖只能截到可視區」限制：讓自動化能穩定截到 table/quote 區塊。

## 已做變更（截至目前）
- **Screenshot flags**：新增 `--screenshot-full`、`--screenshot-scroll-to <text>`、`--screenshot-scroll-y <number>`（`Sources/main.swift` / `Sources/AppDelegate.swift`）。
- **Screenshot 行為**：
  - 預設仍只截 viewport。
  - 指定 `--screenshot-scroll-to` 時，若找不到文字會直接失敗（輸出 `SCREENSHOT_SCROLL_TO_NOT_FOUND ...`）。
  - 指定 `--screenshot-full` 時，native/webkit 都有高度上限（目前 12000px），超過會失敗並提示改用 scroll-to。
- **Native blockquote（regex parser）**：改成 block-level 解析連續 `>` 行，並用 `U+2028` 表示同段落內換行；`>` 空行會產生段落分隔（`\n\n`）。同時移除 `renderBlockquote` 內部多餘的尾端 `\n`，避免雙重換行。
- **AST blockquote soft break**：只在 blockquote context 把 soft break 輸出改成 `U+2028`，避免被當成段落分隔導致間距怪。
- **WebKit table CSS**：`width: max-content` + wrapper `overflow-x: auto`（不再強制 `min-width: 100%`，小表格依內容寬度，避免每欄大片空白）。
- **Native table**：回到較內容導向（`NSTextTable.layoutAlgorithm = .automaticLayoutAlgorithm`；取消百分比均分欄寬）。
- **Fixtures**：新增 `Fixtures/blockquote_spacing.md`、`Fixtures/table_width.md`（含 `SCROLL_TARGET_*` 供 scroll-to 測試）。
- **Tests**：
  - 新增 blockquote spacing 純文字回歸測試（`--native-render-text` 字串包含 `line1\nline2\n\n— author`）。
  - 新增 screenshot + scroll-to smoke regression（`--screenshot-scroll-to SCROLL_TARGET_TABLE`）。
- **Docs**：更新 `README.md` / `todo.md` 說明新 screenshot flags 與 viewport 限制。

## 新發現/修正
- `SCROLL_TARGET_TABLE` 這種含底線的 token 會被 Markdown 規則解讀成 emphasis（例如 `_TARGET_`），導致渲染後底線消失、scroll-to 找不到。
  - 因此 fixtures 與測試改用不含底線的 `SCROLLTARGETTABLE` / `SCROLLTARGETQUOTE`。
- **Native table 寬度策略調整**：根據「小表格不必撐滿視窗、避免每欄大片空白」的需求，改成：
  - 先用字型量測估算各欄內容寬度 → 小表格使用 `absoluteValueType` 設定 table/cell 寬度（更緊湊）。
  - 遇到超寬內容時，以 `maxTableWidth`（從 text container 寬度取得）做上限，交給 TextKit 自動佈局與換行。
- **Gatekeeper / 子行程 SIGKILL**：在此環境下，未簽章的 `mdviewer` 執行檔會被系統拒絕/直接 SIGKILL（測試中表現為 `status=9`）。
  - 修正：`Makefile` 在 `cp` 之後對 `./mdviewer` 做 ad-hoc codesign（`codesign --force --sign - ./mdviewer`），確保 `--help`/測試子行程可正常跑。

## 重要決策/限制
- **scroll-to 是主要可觀測手段**：比 full-page 截圖更穩定，且避免產生超大 PNG。
- **full-page 有硬上限**：防止記憶體/檔案爆掉；超過上限時要求改用 scroll-to。
- **`U+2028` 只作內部排版用途**：debug/test 輸出會把 `U+2028` 正規化成 `\n` 以便做字串比對。

## 待驗證
- ✅ `make test`：53/53 通過。
- ✅ `--native --screenshot-scroll-to`：已在測試中覆蓋並通過（fixture: `Fixtures/table_width.md`）。

## 驗證指令（人工快速檢查）
```bash
make test

./mdviewer --no-activate --native --screenshot .tmp/native-table.png --screenshot-delay 0.2 --screenshot-scroll-to 表格範例 test.md
open .tmp/native-table.png

./mdviewer --no-activate --native --screenshot .tmp/native-quote.png --screenshot-delay 0.2 --screenshot-scroll-to 引用區塊 test.md
open .tmp/native-quote.png
```
