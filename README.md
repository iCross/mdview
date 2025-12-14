# Markdown Viewer

一個使用 Swift + AppKit 開發的 macOS 原生 Markdown 檢視器，支援 **WebKit（HTML/JS）** 與 **Native（NSTextView）** 兩種渲染器，可在「外觀/相容性」與「輕量/原生感」之間切換。

## 目標與渲染路線（WebKit vs 原生 NSTextView）

本專案**目前預設**採用 `WKWebView`（HTML/JS）渲染 Markdown，優點是「快速做出接近 GitHub 的外觀與 code block 高亮」。

如果你的核心目標是 **更小 RAM 佔用、更快啟動、更少依賴**，可以切換成 **Native renderer**：Swift + AppKit + `NSTextView` / `NSAttributedString`（不使用 WebView）。

- **WebKit（目前）**：效果好、功能完整、開發速度快；但 WebKit/JS 會讓記憶體與啟動成本較高。
- **原生 NSTextView（已實作）**：依賴較少、常駐 RAM/啟動成本通常更好，並可做出更「macOS 原生感」的閱讀排版；但要完全對齊 GitHub/GFM 相容性，工程量會比 WebKit 路線高。

## 功能特點

- 📝 **Markdown 渲染** - 使用 marked.js 解析 GitHub Flavored Markdown
- 🎨 **語法高亮** - 使用 highlight.js 提供程式碼高亮
- 🌙 **深色模式** - 自動跟隨系統深色/淺色模式切換
- 📂 **檔案拖放** - 支援拖放 .md/.markdown 檔案
- 🔄 **自動重載** - 檔案變更時自動重新載入
- ⌨️ **快捷鍵支援** - 完整的鍵盤快捷鍵
- 🪶 **Native renderer（NSTextView）** - 原生 code block/quote/table/image（偏 Notes 風格）

## 渲染器切換

- **GUI 選單**：`檢視(View) → 使用 WebKit 渲染器 / 使用原生渲染器（NSTextView）`
- **命令列參數**：
  - `--webkit`（預設）
  - `--native`
  - `--renderer=webkit|native`

## 系統需求

- macOS 10.15 (Catalina) 或更高版本
- Swift 5.0 或更高版本

## 編譯

### Debug 版本

```bash
make debug
# 或
make
```

### Release 版本

```bash
make release
```

### 清除編譯產物

```bash
make clean
```

## 測試

```bash
# 全部測試（包含編譯/CLI/基本行為）
make test

# GUI smoke test：驗證可從 CLI 啟動並建立視窗後自動退出（避免卡住）
make smoke
```

## 使用方式

### 命令列

```bash
# 開啟指定檔案
./mdviewer path/to/file.md

# 開啟應用程式（無檔案）
./mdviewer

# 顯示說明
./mdviewer --help

# 以 Native renderer 開啟
./mdviewer --native test.md
```

### 圖形介面

1. 執行應用程式
2. 拖放 Markdown 檔案到視窗
3. 或使用選單 `File → Open` 開啟檔案

## 快捷鍵

| 快捷鍵 | 功能 |
|--------|------|
| ⌘O | 開啟檔案 |
| ⌘R | 重新載入 |
| ⌘+ | 放大 |
| ⌘- | 縮小 |
| ⌘0 | 實際大小 |
| ⌘W | 關閉視窗 |
| ⌘Q | 結束程式 |
| ⌃⌘F | 全螢幕 |

## 專案結構

```
markdown_swift/
├── Sources/
│   ├── main.swift          # 應用程式入口點
│   ├── AppDelegate.swift   # 應用程式代理
│   ├── MarkdownView.swift  # WebKit 視圖元件
│   ├── NativeMarkdownView.swift # Native 視圖元件（NSTextView）
│   ├── FileHandler.swift   # 檔案處理元件
│   └── MenuBuilder.swift   # 選單建構元件
├── Makefile                # 編譯腳本
├── test.md                 # 測試用 Markdown 檔案
├── Tests/
│   └── test_runner.swift    # 測試執行器
└── README.md               # 本說明文件
```

## 技術架構

- **GUI 框架**: AppKit (NSApplication, NSWindow, NSView)
- **渲染引擎（目前預設）**: WebKit (WKWebView)
  - **Markdown 解析**: marked.js (CDN)
  - **語法高亮**: highlight.js (CDN)
- **渲染引擎（原生 / 已實作）**: AppKit `NSTextView` + `NSAttributedString`（不使用 WebView）
  - **Markdown 解析**: 目前採「簡化 parser + regex」
  - **表格**: `NSTextTable` / `NSTextTableBlock`
  - **圖片**: `NSTextAttachment`（支援相對/絕對路徑）
  - **區塊樣式**: `NSTextBlock`（code block / quote）
  - **語法高亮**: regex 上色（可再升級為 `NSTextStorageDelegate` 增量高亮）
- **檔案監控**: DispatchSourceFileSystemObject

## Native renderer（NSTextView）現況與後續方向

Native renderer 已可使用，目標是「更輕量、更像 macOS Notes 的一致排版」。若想進一步提升相容性與品質，建議：

- **Markdown 解析升級**：改成 AST（例如整合 `cmark-gfm` 或採用 `swift-markdown`），避免 regex 天花板
- **語法高亮升級**：改用 `NSTextStorageDelegate` 做增量高亮（更接近 Editor/Notes 的質感）
- **排版一致性**：以 `textContainerInset` + `NSParagraphStyle` 統一 typography（Notes 風格）

若完全移除 WebKit：更新 `Makefile` 的 `FRAMEWORKS` 並移除 `Sources/MarkdownView.swift` 相關依賴即可。

## 支援的 Markdown 語法

- 標題 (h1-h6)
- 粗體、斜體、刪除線
- 有序/無序列表
- 待辦清單
- 程式碼區塊（含語法高亮）
- 引用區塊
- 表格
- 連結、圖片
- 水平分隔線

## 授權

MIT License

## 開發筆記

此專案使用 `swiftc` 命令列工具編譯，不依賴 Xcode 專案檔案。

```bash
swiftc -o mdviewer Sources/*.swift -framework AppKit -framework WebKit
```

## CLI Debug/Testing（避免卡住）

以下指令會 **快速退出**（不啟動 GUI），適合 CI/除錯：

```bash
# 解析資訊（table/image marker）
./mdviewer --native-dump test.md

# Native 渲染後純文字（用於驗證 fenced code block 不會吃掉後續內容）
./mdviewer --native-render-text test.md
```
