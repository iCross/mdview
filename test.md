# Markdown Viewer 測試文件

這是一個測試 **Markdown Viewer** 功能的示範文件。

## 功能特點

- ✅ Markdown 渲染
- ✅ 程式碼語法高亮
- ✅ 深色模式支援
- ✅ 檔案拖放
- ✅ 自動重新載入

## 程式碼範例

### Swift

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Hello, Markdown Viewer!")
    }
}
```

### Python

```python
def greet(name: str) -> str:
    """Return a greeting message."""
    return f"Hello, {name}!"

if __name__ == "__main__":
    print(greet("World"))
```

### JavaScript

```javascript
const renderMarkdown = (content) => {
    const html = marked.parse(content);
    document.getElementById('content').innerHTML = html;
};
```

## 表格範例

| 功能 | 狀態 | 備註 |
|------|------|------|
| 基本渲染 | ✅ | 完成 |
| 語法高亮 | ✅ | 使用 highlight.js |
| 檔案監控 | ✅ | 自動重載 |
| 深色模式 | ✅ | 自動切換 |

## 引用區塊

> 這是一個引用區塊。
> 可以包含多行內容。
>
> — 作者

## 待辦清單

- [x] 建立基本架構
- [x] 整合 WebKit
- [x] 實作 Markdown 渲染
- [ ] 新增更多功能

## 連結與圖片

這是一個 [GitHub](https://github.com) 連結。

### 外連圖片（placeholder）

![外連圖片 placeholder](https://placehold.co/640x360/png?text=Markdown+Viewer)

---

*感謝使用 Markdown Viewer!*
