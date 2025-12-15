import AppKit
import Foundation

// Shared protocols between renderers.
// NOTE: This project is now Native-only, but we keep this protocol surface
// because AppDelegate/MenuBuilder expect a renderer-agnostic view.

protocol MarkdownDropDelegate: AnyObject {
    func markdownView(_ view: NSView, didReceiveDroppedFile path: String)
}

protocol MarkdownRenderable: AnyObject {
    var dropDelegate: MarkdownDropDelegate? { get set }
    /// Set current document URL for resolving relative resources (images/links).
    func setDocumentURL(_ url: URL?)
    func renderMarkdown(_ content: String)
    func loadWelcomePage()
    func zoomIn()
    func zoomOut()
    func resetZoom()
    /// Rerender current content (for theme/appearance changes).
    func rerender()
}

