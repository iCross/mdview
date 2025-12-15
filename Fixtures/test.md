# Markdown Viewer fixture

這個檔案是給自動化測試與手動 smoke 用的 Markdown 範例（請保持內容穩定）。

## 程式碼範例

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Hello, Markdown Viewer!")
    }
}
```

## 表格範例

| 功能 | 狀態 | 備註 |
|------|------|------|
| 基本渲染 | ✅ | Native (NSTextView) |
| 語法高亮 | ✅ | Highlightr / regex fallback |
| 檔案監控 | ✅ | 自動重載 |
| 深色模式 | ✅ | 跟隨系統 |

## 引用區塊

> 這是一個引用區塊。
> 可以包含多行內容。
>
> — 作者

## 待辦清單

- [x] 建立基本架構
- [x] 實作原生渲染
- [ ] 新增更多功能
