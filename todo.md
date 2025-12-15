# mdview（`mdviewer`）— TODO（進度追蹤，給 LLM）

## 現況
- **Renderer**：Native-only（`NSTextView`）
- **輸入**：本機 `.md`/`.markdown`（支援拖放、檔案變更自動 reload）
- **自動化**：支援 `--smoke-test`、`--screenshot*`、`--dump`、`--render-text`、`--skeleton-check`、`--highlightr-check`

## 不變式（避免回歸）
- Native **不能每字換行**：text container 寬度必須跟著 scrollView 可視寬同步，且要強制 reflow。
- background job/子行程環境 **不要強制 activate**：必要時用 `--no-activate`。
- 所有 build/test/子行程都要有 **timeout + kill**。

## TODO
- [x] 支援 CLI 一次帶多個 `.md/.markdown`（多視窗）與 `Open…` 多選（2025-12-15）
- [x] 加入主題（Theme）：`--theme=system|light|dark` + 選單切換（2025-12-15）
- [x] 啟動後設定 Dock icon（避免非 bundle 顯示預設 `exec` icon）（2025-12-15）

（目前沒有待辦項目）

## 維護提醒（不是 TODO）
- 若新增/調整 CLI flags：同步更新 `Sources/main.swift` 的 `--help` 與 `Tests/test_runner.swift` 覆蓋
- 若改動排版（quote/table/code block）：至少用 `--render-text` 與 `--screenshot-scroll-to` 補一個回歸測試

## 快速指令
```bash
make debug
make test
./mdviewer Fixtures/test.md

# 視覺驗證（PNG）
./mdviewer --no-activate --screenshot .tmp/mdviewer.png --screenshot-delay 0.2 Fixtures/test.md
```
