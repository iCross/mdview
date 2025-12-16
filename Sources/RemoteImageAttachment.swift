import AppKit
import Foundation

extension Notification.Name {
    static let mdviewerRemoteImageDidLoad = Notification.Name("mdviewerRemoteImageDidLoad")
}

/// 非阻塞載入外連圖片的 NSTextAttachment。
///
/// - 目標：不要在 render 當下同步抓網路（避免卡 UI / 影響啟動速度）
/// - 行為：先顯示 placeholder，背景用 URLSession 下載後替換 image，並發送通知讓 view 重新 layout/display。
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
            // 下載失敗：若可 fallback，嘗試一次
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
                // 解析失敗：若可 fallback，嘗試一次
                self.tryFallbackIfNeeded(cacheKey: cacheKey)
                return
            }

            // 同時以「原始 cacheKey」與「實際 URL」做快取，避免 fallback 後仍重複抓圖
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

        // 若 PNG 也曾被快取，直接用
        if let cached = Self.cache.object(forKey: fallbackURL as NSURL) {
            Self.cache.setObject(cached, forKey: cacheKey) // 同時覆蓋原 key，避免重複嘗試 SVG
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
        // Mermaid.ink SVG labels 預設可能使用 foreignObject（AppKit 通常無法渲染），
        // 若仍回到含 foreignObject 的 SVG，就直接視為不可用以觸發 PNG fallback。
        if shouldRejectMermaidInkSVGForForeignObject(data: data, mimeType: mimeType, sourceURL: sourceURL) {
            return nil
        }

        // AppKit 是否能解 SVG 取決於系統/SDK；此處採「先嘗試 NSImage(data:)」，
        // 若失敗則交由呼叫端決定是否走 PNG fallback。
        let img = NSImage(data: data)
        if let img, img.size.width <= 0 || img.size.height <= 0 {
            // 有些向量資源可能回報 0x0，指定一個合理大小避免看不到
            img.size = placeholderSize
        }

        // Mermaid.ink PNG：若用 `width`+`scale` 取得更高像素密度，需把點數 size 調回來避免版面變大。
        if let img {
            adjustMermaidInkHiDPIIfNeeded(img, sourceURL: sourceURL, maxWidth: maxWidth)
        }
        return img
    }

    private static func shouldRejectMermaidInkSVGForForeignObject(data: Data, mimeType: String?, sourceURL: URL) -> Bool {
        guard let host = sourceURL.host?.lowercased(), host == "mermaid.ink" else { return false }
        guard sourceURL.path.hasPrefix("/svg/") else { return false }
        guard looksLikeSVG(data: data, mimeType: mimeType) else { return false }

        // 只看前面一段即可（避免把大圖整個 decode 成字串）
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

        // 只處理 PNG（SVG 不需要）
        let type = items.first(where: { $0.name == "type" })?.value?.lowercased()
        guard type == "png" else { return }

        // scale 只有在帶 width/height 時才會出現；若沒有，就視為 1x。
        guard let scaleStr = items.first(where: { $0.name == "scale" })?.value,
              let desiredScale = Double(scaleStr),
              desiredScale > 1.0 else {
            return
        }

        // 取 bitmap 像素尺寸（沒有就跳過）
        guard let rep = img.representations.compactMap({ $0 as? NSBitmapImageRep }).first else { return }
        let pxW = CGFloat(rep.pixelsWide)
        let pxH = CGFloat(rep.pixelsHigh)
        guard pxW > 1, pxH > 1 else { return }

        // mermaid.ink 的行為偏向「輸出像素寬度 <= width*scale」，且不會放大超過 diagram 的自然尺寸。
        // 因此不能一律除以 desiredScale；需依「實際像素 / maxWidth」計算有效縮放，避免小圖被縮小。
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

        // 內容偵測：trim leading whitespace，檢查 <svg / <?xml ... <svg
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

