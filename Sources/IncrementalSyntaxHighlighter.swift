import AppKit
import Foundation
import Highlightr

/// Incremental syntax highlighting helper (Editor-ready).
///
/// 設計原則：
/// - 只改 attributes（不改 characters）
/// - 用 guard 避免在 didProcessEditing 內造成遞迴編輯/崩潰
final class IncrementalSyntaxHighlighter: NSObject, NSTextStorageDelegate {
    private let highlightr: Highlightr?
    private var isApplying: Bool = false

    /// Highlightr language name/alias（nil 代表 auto-detect）
    var language: String?

    /// 只套用這些 attributes，避免破壞既有 paragraphStyle/background 等樣式
    private let allowedKeys: Set<NSAttributedString.Key> = [
        .foregroundColor,
        .font
    ]

    init(language: String? = nil, themeName: String = "paraiso-light", codeFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)) {
        self.highlightr = Highlightr()
        self.language = language
        super.init()

        if let hl = highlightr {
            _ = hl.setTheme(to: themeName)
            hl.theme.setCodeFont(codeFont)
        }
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard !isApplying else { return }
        guard editedMask.contains(.editedCharacters) else { return }
        guard let hl = highlightr else { return }

        isApplying = true
        defer { isApplying = false }

        let full = NSRange(location: 0, length: textStorage.length)
        let source = textStorage.string
        guard !source.isEmpty else { return }

        guard let highlighted = hl.highlight(source, as: language, fastRender: true) else { return }

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        // 先移除會被我們控制的 attributes（保留 paragraphStyle/background 等）
        for key in allowedKeys {
            textStorage.removeAttribute(key, range: full)
        }

        // 只把 Highlightr 產出的「必要 attributes」疊回去
        highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length), options: []) { attrs, range, _ in
            var filtered: [NSAttributedString.Key: Any] = [:]
            for (k, v) in attrs where allowedKeys.contains(k) {
                filtered[k] = v
            }
            if !filtered.isEmpty {
                textStorage.addAttributes(filtered, range: range)
            }
        }
    }
}

