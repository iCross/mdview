# markdown_swift（`mdviewer`）— LLM 專案入口

## 目標
macOS Markdown Reader（AppKit）。支援兩種渲染器：
- **WebKit（deprecated）**：`WKWebView`（HTML/JS；marked.js / highlight.js 走 CDN）。仍可用但不建議，後續預計移除；建議改用 `--native`。
- **Native**：`NSTextView`（TextKit；支援 `regex` 或 `swift-markdown` AST 管線；code block 主要用 Highlightr）

## 最常用指令
```bash
make debug
make test
make smoke
./mdviewer test.md
./mdviewer --help
```

## CLI（以程式碼為準：`Sources/main.swift`）
- **Renderer**：`--webkit`（deprecated；目前仍可用且可能仍為預設）、`--native`、`--renderer=webkit|native`
- **Native pipeline**：`--native-pipeline=regex|ast`、`--native-ast`
- **前景/背景啟動注意事項**：
  - 若你用 `&` 把它當 background job 跑，或在某些自動化/子行程環境，強制 `activate` 可能導致程式被系統直接終止；可加 `--no-activate` 避免。
- **CI/除錯（不啟動 GUI）**：
  - `--native-dump <file.md>`
  - `--native-render-text <file.md>`
  - `--native-skeleton-check`
  - `--highlightr-check`
- **GUI smoke**：`--smoke-test`（建立視窗後自動退出；用來避免 WebKit 初始化造成「視窗不出現」的誤判）
- **GUI screenshot（給 LLM / CI 做視覺驗證）**：
  - `--screenshot <out.png>`（啟動 GUI、渲染後輸出 PNG，然後自動退出）
  - `--screenshot-delay <sec>`（等待秒數；預設 1.0，WebKit 建議 >= 1.0）
  - `--no-activate`（避免在 background job/子行程環境強制拉前景）

## GUI 截圖（給 LLM / CI）
- **用途**：把 GUI 渲染結果轉成 PNG，方便在 CI/agent 端檢查 table / quote / code block 等視覺結果。
- **輸出位置**：建議用 repo 內的 `.tmp/`（已在 `.gitignore` 忽略）；輸出資料夾會自動建立。
- **成功/失敗訊號**：
  - 成功：stdout 會印 `SCREENSHOT_OK <path>`，exit code = 0
  - 失敗：stdout 會印 `SCREENSHOT_FAIL <path>`，exit code = 1
  - 超時：stdout 會印 `SCREENSHOT_TIMEOUT <path>`，exit code = 2

範例（Native，建議）：
```bash
./mdviewer --no-activate --native --screenshot .tmp/mdviewer-native.png --screenshot-delay 0.2 test.md
open .tmp/mdviewer-native.png
```

範例（WebKit，deprecated；通常需要更久的 delay）：
```bash
./mdviewer --no-activate --webkit --screenshot .tmp/mdviewer-webkit.png --screenshot-delay 1.0 test.md
open .tmp/mdviewer-webkit.png
```

## 程式碼入口（找功能先看這些）
- `Sources/main.swift`：CLI flags / debug-only 路徑 / App 啟動
- `Sources/AppDelegate.swift`：視窗、渲染器切換、載檔、檔案監控、拖放
- `Sources/MarkdownView.swift`：WebKit renderer
- `Sources/NativeMarkdownView.swift`：Native renderer（width sync / reflow 關鍵也在這）
- `Sources/ASTMarkdownRenderer.swift`：AST 管線（`swift-markdown`）
- `Sources/FileHandler.swift`：讀檔 + 檔案變更監控
- `Sources/MenuBuilder.swift`：選單/快捷鍵
- `Tests/test_runner.swift`：測試入口

## 不變式（回歸最常發生在這）
- **Native 不能每字換行**：`NSTextContainer` 寬度要跟著 `NSScrollView` 可視寬同步，並在幾何變更時強制 reflow。
- **所有 build/test/子行程必須有 timeout**：避免卡死（Makefile 已包 timeout；測試也應同樣保守）。

## 測試在「無法啟動子行程 GUI」環境的處理
預設 `make test` 會把「mdviewer 子行程不可執行」視為失敗（避免掩蓋回歸）。
若你在特殊環境（例如無 GUI session/平台限制）需要跳過這段，改用：

```bash
MDVIEWER_ALLOW_SKIP_SUBPROCESS_TESTS=1 make test
```

## 其他文件（都以「給 LLM 用」為前提）
- `todo.md`：僅保留仍未完成的 TODO 與關鍵決策/不變式
