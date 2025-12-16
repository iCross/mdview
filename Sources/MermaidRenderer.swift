import AppKit
import Foundation

/// Mermaid fenced code block renderer (via mermaid.ink).
///
/// 設計目標：
/// - 不依賴 `mmdc` / mermaid-cli
/// - 預設會嘗試顯示 Mermaid diagram（以外連圖片載入）
/// - 保留 code block 原文；diagram 由上層 renderer 另行插入
enum MermaidRenderer {
    /// 讓 PNG 有更好的文字銳利度（retina/縮放時）；對 mermaid.ink 來說 `scale` 必須搭配 `width/height`。
    private static let pngRasterScale: Int = 2

    /// 產生 mermaid.ink 的 SVG diagram URL（pako: zlib-deflate + base64url）。
    static func makeDiagramURL(code: String, appearance: NSAppearance?) -> URL? {
        makeMermaidInkURL(endpoint: .svg, code: code, appearance: appearance)
    }
    
    /// 產生「原版」mermaid.ink SVG URL（不注入 htmlLabels:false；用於對比原始渲染結果）。
    ///
    /// - Note: 可用於查看 mermaid.ink 的原始輸出（可能含 foreignObject/HTML labels）。
    static func makeOriginalDiagramURL(code: String, appearance: NSAppearance?) -> URL? {
        makeMermaidInkURL(endpoint: .svg, code: code, appearance: appearance, injectNativeSVGConfig: false)
    }
    
    /// 產生對比資訊：原版 vs. 修改版（native SVG）的 URL。
    ///
    /// - Returns: 包含兩個 URL 的字串，方便在瀏覽器中對比渲染結果。
    static func makeDiagramURLComparison(code: String, appearance: NSAppearance?) -> String? {
        guard let originalURL = makeOriginalDiagramURL(code: code, appearance: appearance),
              let nativeURL = makeDiagramURL(code: code, appearance: appearance) else {
            return nil
        }
        return """
        原版 (htmlLabels 預設):
        \(originalURL.absoluteString)
        
        修改版 (htmlLabels:false):
        \(nativeURL.absoluteString)
        """
    }

    /// 產生可顯示於 NSTextView 的外連圖片附件。
    ///
    /// - Note: 會立即觸發非阻塞下載（不等待網路）。
    static func makeAttachment(code: String, theme: NativeMarkdownTheme, maxWidth: CGFloat?) -> NSAttributedString? {
        let appearance = NSApp?.effectiveAppearance
        // 需求：render 結果要和 mermaid.ink「原版」一致（例如 edge labels 會有白底框，文字不應壓在線條上）。
        //
        // 現況：
        // - AppKit 的 SVG decoder 對 Mermaid 產出的 SVG（尤其是文字 baseline/foreignObject）支援不完整，
        //   即使透過 `htmlLabels:false` 轉成純 SVG text，也可能出現文字位置偏移（例如壓到線條上）。
        //
        // 解法：
        // - 顯示時**優先使用 PNG**（由 mermaid.ink rasterize，效果與瀏覽器渲染一致）
        // - link 仍指向原始 SVG（方便使用者在瀏覽器查看/另存向量）
        let wLimit: CGFloat = {
            if let maxWidth { return max(120, maxWidth) }
            return CGFloat(720.0 * theme.zoom)
        }()

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 以顯示用 maxWidth（點數）作為 raster request 的 width，上層再用 scale/downscale 讓顯示保持在點數但更銳利。
        let rasterWidth = Int(ceil(max(1, wLimit)))
        let originalPNGURL = makeMermaidInkURL(
            endpoint: .png,
            code: trimmed,
            appearance: appearance,
            rasterWidth: rasterWidth,
            rasterScale: pngRasterScale,
            injectNativeSVGConfig: false
        )
        let originalSVGURL = makeMermaidInkURL(
            endpoint: .svg,
            code: trimmed,
            appearance: appearance,
            injectNativeSVGConfig: false
        )

        guard let primaryURL = originalPNGURL ?? originalSVGURL else { return nil }

        let attachment = RemoteImageAttachment(url: primaryURL, fallbackURL: nil, maxWidth: wLimit, zoom: theme.zoom)
        attachment.startIfNeeded()

        let out = NSMutableAttributedString(attachment: attachment)
        // link 指向「原版 SVG」（向量、且可在瀏覽器看到完整 HTML labels）
        let linkURL = originalSVGURL ?? primaryURL
        out.addAttribute(.link, value: linkURL.absoluteString, range: NSRange(location: 0, length: out.length))
        return out
    }

    // MARK: - Mermaid.ink URL generation

    private enum MermaidInkEndpoint {
        case svg
        case png
    }

    private static func makeMermaidInkURL(
        endpoint: MermaidInkEndpoint,
        code: String,
        appearance: NSAppearance?,
        rasterWidth: Int? = nil,
        rasterScale: Int? = nil,
        injectNativeSVGConfig: Bool = true
    ) -> URL? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // mermaid.ink 目前可穩定支援 `/svg/<base64url(utf8)>` 形式（不需 pako 壓縮）。
        // 先以最簡單且可預期的 encoding 走通，避免 API 版本差異導致 diagram 全部變成 error SVG。
        let finalCode = injectNativeSVGConfig ? makeCodeForNativeSVGDisplay(trimmed) : trimmed
        guard let payload = makeBase64URLPayload(code: finalCode) else { return nil }

        let isDark = (appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let theme = isDark ? "dark" : "default"

        var c = URLComponents()
        c.scheme = "https"
        c.host = "mermaid.ink"

        switch endpoint {
        case .svg:
            c.path = "/svg/\(payload)"
            c.queryItems = [
                URLQueryItem(name: "theme", value: theme),
                URLQueryItem(name: "bgColor", value: "transparent")
            ]
        case .png:
            // PNG fallback：用 img endpoint + type=png
            c.path = "/img/\(payload)"
            var items: [URLQueryItem] = [
                URLQueryItem(name: "type", value: "png"),
                URLQueryItem(name: "theme", value: theme),
                URLQueryItem(name: "bgColor", value: "transparent")
            ]
            // mermaid.ink：scale 必須搭配 width 或 height；這裡用 width 作為上限（像素），讓大圖可拿到 2x raster 再由 client downscale。
            if let rasterWidth, rasterWidth > 0 {
                items.append(URLQueryItem(name: "width", value: String(rasterWidth)))
            }
            if let rasterScale, rasterScale > 1, rasterWidth != nil {
                items.append(URLQueryItem(name: "scale", value: String(rasterScale)))
            }
            c.queryItems = items
        }

        return c.url
    }

    private static func makeBase64URLPayload(code: String) -> String? {
        guard let data = code.data(using: .utf8) else { return nil }
        // base64url: + -> -, / -> _, trim '='
        var b64 = data.base64EncodedString()
        b64 = b64.replacingOccurrences(of: "+", with: "-")
        b64 = b64.replacingOccurrences(of: "/", with: "_")
        b64 = b64.replacingOccurrences(of: "=", with: "")
        return b64
    }

    /// 讓 mermaid.ink 回傳「不含 foreignObject」的 SVG（以便 AppKit 可正確渲染 labels）。
    ///
    /// - Note:
    ///   - Mermaid 的 `htmlLabels:false` 在不同版本/diagram type 上的行為略有差異。
    ///   - 目前觀察：需要同時設 top-level 與 flowchart 的 htmlLabels 才能完全移除 foreignObject。
    private static func makeCodeForNativeSVGDisplay(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // 若使用者已提供 init directive，就尊重原始設定（避免覆寫行為）。
        if trimmed.contains("%%{init:") { return trimmed }

        let initDirective = #"%%{init: {"htmlLabels": false, "flowchart": {"htmlLabels": false}} }%%"#
        return initDirective + "\n" + trimmed
    }
}

