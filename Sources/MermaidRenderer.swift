import AppKit
import Foundation

/// Mermaid fenced code block renderer (via mermaid.ink).
///
/// Design goals:
/// - Do not depend on `mmdc` / mermaid-cli
/// - Try to show Mermaid diagrams by default (loaded as a remote image)
/// - Keep the original code block text; the diagram is inserted by the higher-level renderer
enum MermaidRenderer {
    /// Improve PNG text sharpness (retina/zoom). On mermaid.ink, `scale` must be used together with `width/height`.
    private static let pngRasterScale: Int = 2

    /// Build the mermaid.ink SVG diagram URL (base64url payload).
    static func makeDiagramURL(code: String, appearance: NSAppearance?) -> URL? {
        makeMermaidInkURL(endpoint: .svg, code: code, appearance: appearance)
    }
    
    /// Build the "original" mermaid.ink SVG URL (do not inject htmlLabels:false; used to compare with the default rendering).
    ///
    /// - Note: Useful for inspecting mermaid.ink's default output (may include foreignObject/HTML labels).
    static func makeOriginalDiagramURL(code: String, appearance: NSAppearance?) -> URL? {
        makeMermaidInkURL(endpoint: .svg, code: code, appearance: appearance, injectNativeSVGConfig: false)
    }
    
    /// Build comparison text: original vs. modified (native SVG) URLs.
    ///
    /// - Returns: A string containing both URLs for easy side-by-side comparison in a browser.
    static func makeDiagramURLComparison(code: String, appearance: NSAppearance?) -> String? {
        guard let originalURL = makeOriginalDiagramURL(code: code, appearance: appearance),
              let nativeURL = makeDiagramURL(code: code, appearance: appearance) else {
            return nil
        }
        return """
        Original (default htmlLabels):
        \(originalURL.absoluteString)
        
        Modified (htmlLabels:false):
        \(nativeURL.absoluteString)
        """
    }

    /// Build a remote-image attachment that can be displayed in NSTextView.
    ///
    /// - Note: Starts a non-blocking download immediately (does not wait for the network).
    static func makeAttachment(code: String, theme: NativeMarkdownTheme, maxWidth: CGFloat?) -> NSAttributedString? {
        let appearance = NSApp?.effectiveAppearance
        // Requirement: rendering should match mermaid.ink's "original" output as closely as possible
        // (e.g. edge labels with a white background; text should not overlap lines).
        //
        // Reality:
        // - AppKit's SVG decoding for Mermaid-generated SVG (especially baseline/foreignObject) is imperfect.
        //   Even with `htmlLabels:false` producing pure SVG text, label positions can be off.
        //
        // Strategy:
        // - Prefer PNG for display (rasterized by mermaid.ink; matches browser rendering)
        // - Keep links pointing to the original SVG (easy to view/save as vector in a browser)
        let wLimit: CGFloat = {
            if let maxWidth { return max(120, maxWidth) }
            return CGFloat(720.0 * theme.zoom)
        }()

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Use display maxWidth (points) as the raster request width; then scale/downscale for sharper output.
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
        // Link to the "original SVG" (vector; view full HTML labels in a browser).
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
        // mermaid.ink reliably supports `/svg/<base64url(utf8)>` (no pako compression required).
        // Use the simplest predictable encoding to avoid API/version drift turning diagrams into error SVGs.
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
            // PNG via /img endpoint + type=png
            c.path = "/img/\(payload)"
            var items: [URLQueryItem] = [
                URLQueryItem(name: "type", value: "png"),
                URLQueryItem(name: "theme", value: theme),
                URLQueryItem(name: "bgColor", value: "transparent")
            ]
            // mermaid.ink: scale must be paired with width or height. Here we use width as a pixel upper bound,
            // request a 2x raster, then let the client downscale to points.
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

    /// Make mermaid.ink return an SVG without foreignObject (so AppKit can render labels correctly).
    ///
    /// - Note:
    ///   - Mermaid's `htmlLabels:false` behavior varies across versions/diagram types.
    ///   - Current observation: setting both top-level and flowchart htmlLabels helps fully remove foreignObject.
    private static func makeCodeForNativeSVGDisplay(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // If the user already provided an init directive, respect it (avoid overriding behavior).
        if trimmed.contains("%%{init:") { return trimmed }

        let initDirective = #"%%{init: {"htmlLabels": false, "flowchart": {"htmlLabels": false}} }%%"#
        return initDirective + "\n" + trimmed
    }
}

