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
    private let maxWidth: CGFloat
    private var didStart: Bool = false

    init(url: URL, maxWidth: CGFloat, zoom: Double) {
        self.url = url
        self.maxWidth = max(120, maxWidth)
        super.init(data: nil, ofType: nil)

        self.image = Self.makePlaceholderImage(size: NSSize(width: min(360, self.maxWidth), height: CGFloat(180 * zoom)))
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

        var req = URLRequest(url: url)
        req.timeoutInterval = 4

        let task = Self.session.dataTask(with: req) { data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            Self.cache.setObject(img, forKey: self.url as NSURL)
            DispatchQueue.main.async {
                self.applyImage(img)
            }
        }
        task.resume()
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

