import AppKit
import Foundation

extension Notification.Name {
    static let mdviewerRemoteImageDidLoad = Notification.Name("mdviewerRemoteImageDidLoad")
}

/// An NSTextAttachment that loads remote images non-blockingly.
///
/// - Goal: do not fetch the network synchronously during render (avoid UI stalls / slow startup)
/// - Behavior: show a placeholder first, download via URLSession in the background, then replace the image and post a notification for relayout/display.
final class RemoteImageAttachment: NSTextAttachment {
    private static let cache = NSCache<NSURL, NSImage>()
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 6
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()

    private let url: URL
    private let fallbackURL: URL?
    private let maxWidth: CGFloat
    private var didStart: Bool = false
    private var didTryFallback: Bool = false
    private let placeholderSize: NSSize

    init(url: URL, fallbackURL: URL? = nil, maxWidth: CGFloat, zoom: Double) {
        let resolvedMaxWidth = max(120, maxWidth)
        let resolvedPlaceholder = NSSize(width: min(360, resolvedMaxWidth), height: CGFloat(180 * zoom))

        self.url = url
        self.fallbackURL = fallbackURL
        self.maxWidth = resolvedMaxWidth
        self.placeholderSize = resolvedPlaceholder
        super.init(data: nil, ofType: nil)

        self.image = Self.makePlaceholderImage(size: resolvedPlaceholder)
        self.bounds = NSRect(origin: .zero, size: self.image?.size ?? NSSize(width: 240, height: 140))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        if let cached = Self.cache.object(forKey: url as NSURL) {
            applyImage(cached)
            return
        }

        fetch(url: url, cacheKey: url as NSURL)
    }

    private func fetch(url: URL, cacheKey: NSURL) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 4

        let task = Self.session.dataTask(with: req) { data, response, error in
            // Download failed: try fallback once if available.
            if data == nil || error != nil {
                self.tryFallbackIfNeeded(cacheKey: cacheKey)
                return
            }
            guard let data else {
                self.tryFallbackIfNeeded(cacheKey: cacheKey)
                return
            }

            let mimeType = response?.mimeType
            guard let img = Self.decodeImage(
                data: data,
                mimeType: mimeType,
                placeholderSize: self.placeholderSize,
                sourceURL: url,
                maxWidth: self.maxWidth
            ) else {
                // Decode failed: try fallback once if available.
                self.tryFallbackIfNeeded(cacheKey: cacheKey)
                return
            }

            // Cache under both the original cacheKey and the actual URL to avoid refetching after fallback.
            Self.cache.setObject(img, forKey: cacheKey)
            Self.cache.setObject(img, forKey: url as NSURL)
            DispatchQueue.main.async {
                self.applyImage(img)
            }
        }
        task.resume()
    }

    private func tryFallbackIfNeeded(cacheKey: NSURL) {
        guard !didTryFallback else { return }
        guard let fallbackURL else { return }
        didTryFallback = true

        // If the fallback was already cached, use it directly.
        if let cached = Self.cache.object(forKey: fallbackURL as NSURL) {
            Self.cache.setObject(cached, forKey: cacheKey) // overwrite original key to avoid retrying SVG
            DispatchQueue.main.async {
                self.applyImage(cached)
            }
            return
        }

        fetch(url: fallbackURL, cacheKey: cacheKey)
    }

    private func applyImage(_ img: NSImage) {
        self.image = img

        let size = img.size
        if size.width > 0 && size.height > 0 {
            let ratio = min(1.0, maxWidth / size.width)
            let displaySize = NSSize(width: size.width * ratio, height: size.height * ratio)
            self.bounds = NSRect(x: 0, y: 0, width: displaySize.width, height: displaySize.height)
        }

        NotificationCenter.default.post(name: .mdviewerRemoteImageDidLoad, object: self)
    }

    private static func decodeImage(data: Data, mimeType: String?, placeholderSize: NSSize, sourceURL: URL, maxWidth: CGFloat) -> NSImage? {
        // Mermaid.ink SVG labels may use foreignObject by default (AppKit often can't render it).
        // If we still get an SVG containing foreignObject, treat it as unusable and trigger PNG fallback.
        if shouldRejectMermaidInkSVGForForeignObject(data: data, mimeType: mimeType, sourceURL: sourceURL) {
            return nil
        }

        // Whether AppKit can decode SVG depends on system/SDK. Try `NSImage(data:)` first;
        // if it fails, let the caller decide whether to use PNG fallback.
        let img = NSImage(data: data)
        if let img, img.size.width <= 0 || img.size.height <= 0 {
            // Some vector resources can report 0x0; assign a reasonable size so it stays visible.
            img.size = placeholderSize
        }

        // Mermaid.ink PNG: if we requested higher pixel density via `width`+`scale`, adjust point size back to avoid enlarging layout.
        if let img {
            adjustMermaidInkHiDPIIfNeeded(img, sourceURL: sourceURL, maxWidth: maxWidth)
        }
        return img
    }

    private static func shouldRejectMermaidInkSVGForForeignObject(data: Data, mimeType: String?, sourceURL: URL) -> Bool {
        guard let host = sourceURL.host?.lowercased(), host == "mermaid.ink" else { return false }
        guard sourceURL.path.hasPrefix("/svg/") else { return false }
        guard looksLikeSVG(data: data, mimeType: mimeType) else { return false }

        // Only inspect the prefix (avoid decoding huge SVGs into a full string).
        let prefix = data.prefix(200_000)
        guard let s = String(data: prefix, encoding: .utf8) else { return false }
        return s.contains("<foreignObject")
    }

    private static func adjustMermaidInkHiDPIIfNeeded(_ img: NSImage, sourceURL: URL, maxWidth: CGFloat) {
        guard maxWidth > 1 else { return }
        guard let host = sourceURL.host, host.lowercased() == "mermaid.ink" else { return }
        guard sourceURL.path.hasPrefix("/img/") else { return }

        guard let c = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else { return }
        let items = c.queryItems ?? []

        // Only for PNG (not needed for SVG).
        let type = items.first(where: { $0.name == "type" })?.value?.lowercased()
        guard type == "png" else { return }

        // `scale` only appears with width/height; if absent, treat it as 1x.
        guard let scaleStr = items.first(where: { $0.name == "scale" })?.value,
              let desiredScale = Double(scaleStr),
              desiredScale > 1.0 else {
            return
        }

        // Read bitmap pixel size (skip if unavailable).
        guard let rep = img.representations.compactMap({ $0 as? NSBitmapImageRep }).first else { return }
        let pxW = CGFloat(rep.pixelsWide)
        let pxH = CGFloat(rep.pixelsHigh)
        guard pxW > 1, pxH > 1 else { return }

        // mermaid.ink tends to output pixel width <= width*scale and won't upscale beyond the diagram's natural size.
        // So we can't always divide by desiredScale; compute an effective scale from (actual pixels / maxWidth) to avoid shrinking small diagrams.
        let ratio = pxW / maxWidth
        let effective = min(CGFloat(desiredScale), max(1.0, ratio))
        let newSize = NSSize(width: pxW / effective, height: pxH / effective)
        if newSize.width > 1, newSize.height > 1 {
            img.size = newSize
        }
    }

    private static func looksLikeSVG(data: Data, mimeType: String?) -> Bool {
        if let mimeType, mimeType.lowercased().contains("image/svg+xml") {
            return true
        }

        // Content sniffing: trim leading whitespace, check for <svg or <?xml ... <svg.
        let prefix = data.prefix(512)
        guard var s = String(data: prefix, encoding: .utf8) else { return false }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("<svg") { return true }
        if s.hasPrefix("<?xml") && s.contains("<svg") { return true }
        return false
    }

    private static func makePlaceholderImage(size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        NSColor.clear.setFill()
        rect.fill()

        let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.92, alpha: 1.0).setFill()
        bg.fill()

        NSColor(calibratedWhite: 0.82, alpha: 1.0).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        let title = "IMG"
        let font = NSFont.systemFont(ofSize: min(40, size.height * 0.35), weight: .semibold)
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0),
            .paragraphStyle: p
        ]
        let s = NSAttributedString(string: title, attributes: attrs)
        let tSize = s.size()
        let tRect = NSRect(
            x: (size.width - tSize.width) / 2,
            y: (size.height - tSize.height) / 2,
            width: tSize.width,
            height: tSize.height
        )
        s.draw(in: tRect)

        return img
    }
}

