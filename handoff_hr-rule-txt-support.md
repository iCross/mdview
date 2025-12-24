# mdview 橫線渲染與純文字支援 Handoff

## 問題
1. `---` (horizontal rule) 渲染為短線且置中，使用者期望是全寬橫線靠左對齊
2. 希望支援開啟 `.txt` 等純文字檔案（目前只接受 `.md` / `.markdown`）

## 根因
- `NativeMarkdownView.swift:942-954` 的 `renderHorizontalRule()` 使用固定 10 個字元 `──────────` + 置中對齊
- `AppDelegate.swift:226,298,315` 檔案過濾邏輯硬編碼檢查 `.md` / `.markdown` 副檔名

## 關鍵檔案
- `Sources/NativeMarkdownView.swift`: 原生 Markdown 渲染器，橫線渲染邏輯在 942-955 行
- `Sources/AppDelegate.swift`: 檔案開啟與過濾邏輯（226, 298, 315 行）
- `README.md`: 專案文件（已整理 todo.md 的開發注意事項到此）

## 已完成
- [x] 整理文檔：合併 todo.md 與 mdview-multiopen-theme-icon-tracker.md 到 README.md
- [x] `git rm` 移除舊追蹤文件
- [x] 調查橫線渲染邏輯（NativeMarkdownView.swift:942-954）
- [x] 調查檔案類型過濾邏輯（AppDelegate.swift 三處）
- [x] 修復橫線渲染：改為 100 個 `─` 字元 + 靠左對齊（NativeMarkdownView.swift:942-955）
- [x] 修改 `AppDelegate.swift` 的檔案過濾邏輯，支援 `.txt` 等純文字副檔名
- [x] 優化 window/tab title：移除 "Markdown Viewer -" 前綴，只顯示檔名
- [x] 建立測試用檔案（test-hr.md, test.txt）並測試開啟功能
- [x] 執行完整測試確認改動未破壞現有功能（57/57 通過）

## 待辦
- [ ] 更新 CLI `--help` 說明與文件，註明支援的檔案類型（目前支援 .md, .markdown, .txt）
- [ ] （可選）更新 README.md 說明新的 window title 行為

## 關鍵指令
```bash
# 編譯與測試
make debug
make test

# 手動驗證橫線渲染（test.md 需加入 --- 測試行）
./mdview Fixtures/test.md

# 驗證純文字開啟（待實作）
echo "Hello World" > /tmp/test.txt
./mdview /tmp/test.txt
```

## 注意事項
- 橫線渲染已修改為靠左對齊，使用 100 個字元確保填滿寬度
- 檔案過濾邏輯有三處需同步修改（已完成）：
  1. `AppDelegate.swift:226` - `application(_:openFile:)` ✅
  2. `AppDelegate.swift:298` - CLI 參數過濾 ✅
  3. `AppDelegate.swift:315` - Open 對話框過濾 ✅
- 純文字檔案應視為「無 Markdown 語法的純文本」直接渲染
- Window title 行為：
  - 有開啟檔案時：只顯示檔名（例：`test.md`）
  - 無開啟檔案時：顯示 `Markdown Viewer`

## 建議下一步
1. ✅ 在 `Fixtures/test.md` 加入 `---` 測試行，編譯並確認橫線顯示正確
2. ✅ 修改 `AppDelegate.swift` 三處檔案過濾，加入 `.txt` 支援
3. ✅ 建立 `Fixtures/test.txt` 測試檔案，驗證純文字開啟功能
4. ✅ 執行 `make test` 確保所有測試通過
5. 更新 `--help` 說明，註明支援的檔案類型
6. （可選）更新 README.md 說明 window title 行為與支援的檔案類型
