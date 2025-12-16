# mdview tracker：multi-open / themes / app icon / native flags

日期：2025-12-15

## 目標
- CLI 參數可一次帶多個 `.md/.markdown`，一次開多個檔案
- 加入 theme：system/light/dark（可用 CLI 及選單切換）
- 啟動後 Dock icon 不再是預設 `exec` icon
- 釐清並整理「native/webkit」過去遺留的命名/flags（保留相容，介面更直覺）

## 調查筆記
### 1) `IMKCFRunLoopWakeUpReliable` 訊息
觀察到執行時出現類似：

- `error messaging the mach port for IMKCFRunLoopWakeUpReliable`

結論（初步）：
- **不是本專案自行 print**（repo 內搜尋 `IMKCFRunLoopWakeUpReliable` / `InputMethodKit` 無命中）。
- 高機率來自 **macOS InputMethodKit / TextKit**：初始化 `NSTextView` 會觸發文字輸入子系統，某些情境會輸出這類 error log（通常不影響功能）。
- 對策方向：
  - 文件化為 FAQ（可忽略、功能正常即可）。
  - 若要乾淨 log：測試 runner 分離 stdout/stderr 或過濾；或改成 `.app bundle` 形式啟動以降低出現機率。

### 2) 目前 CLI 與 renderer 狀態
- 專案已是 **Native-only**（WebKit 已移除）。
- CLI 已改為 **不再提供 `--native`**；pipeline 以 `--pipeline` / `--ast` 表示（只保留一套介面）。

### 3) 補充：AppKit `openFile` 事件與 argv 互動
- 在某些啟動路徑，AppKit 可能會把「非 option 的 argv」也當成 `application(_:openFile:)` 事件丟進來。\n  例：`--screenshot <out.png>` 的 `<out.png>` 會被誤當成要開的文件，導致 screenshot 測試不穩定。\n- 對策：`openFile` 僅接受 `.md/.markdown`；screenshot 模式也只挑第一個 Markdown 檔作為開啟目標。

## 變更清單（待完成）
- [x] CLI：支援多個檔案參數 -> 多視窗（`AppDelegate` + `MarkdownWindowController`）
- [x] Menu：Open… 支援多選（`NSOpenPanel.allowsMultipleSelection = true`）
- [x] Theme：`--theme=system|light|dark` + 選單切換 + 可重渲染（`MarkdownRenderable.rerender()`）
- [x] Icon：啟動後設定 `NSApp.applicationIconImage`（避免 exec icon；目前為程式內產生的簡易 MD 圖示）
- [x] Docs：README/todo 更新 + FAQ（IMK log）
- [ ] Tests：更新並跑 `make test`

## 驗收
- CLI：`./mdview a.md b.md c.md` 會同時開多個視窗
- Theme：切換後 code highlight 與背景/文字色系一致更新
- Dock icon：顯示 mdview icon（非 exec）
- `make test` 通過

## 後續補充（2025-12-15）
- 清單縮排改為更接近 macOS Notes：符號/數字也會跟著縮排，並用 tab stop + hanging indent 對齊文字。
- `Fixtures/test.md` 擴充：加入 H1/H2/H3、圖片語法、bullet/ordered list、mermaid 範例。
- Mermaid 支援：遇到 ` ```mermaid ` code block 時會保留原始碼，並在下方額外顯示 diagram（透過 `mermaid.ink` 產生 SVG；需要網路；非阻塞載入）。
