import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Feeds photos that arrive natively - dropped on the window, opened with
/// "Open With", dropped on the Dock icon, or picked in the open panel - into
/// the page, and remembers the folder the current photo came from so exports
/// default back to it.
final class PhotoBridge {
    static let shared = PhotoBridge()

    weak var webView: WKWebView?
    private(set) var sourceDirectory: URL?
    private var pending: URL?

    /// Hand a photo to the page, queueing it if the page is still loading
    /// (opening the app by dropping a file on its icon gets here first).
    func open(_ url: URL) {
        noteSource(url)
        guard let webView, !webView.isLoading else {
            pending = url
            return
        }
        deliver(url, to: webView)
    }

    func noteSource(_ url: URL) {
        sourceDirectory = url.deletingLastPathComponent()
    }

    func flushPending() {
        guard let webView, let url = pending else { return }
        pending = nil
        deliver(url, to: webView)
    }

    /// Formats WebKit renders directly; anything else (HEIC from an iPhone,
    /// camera RAW) is transcoded to PNG before being handed over.
    private static let webSafeMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp", "image/tiff",
    ]

    private func deliver(_ url: URL, to webView: WKWebView) {
        guard let dataURL = dataURL(for: url) else { return }
        webView.callAsyncJavaScript(
            "window.croppenheimerLoadImage(src, name)",
            arguments: ["src": dataURL, "name": url.lastPathComponent],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    // A data: URL keeps the photo same-origin, so the page's export canvas
    // stays untainted and toBlob() still works.
    private func dataURL(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
           Self.webSafeMIMETypes.contains(mime) {
            return "data:\(mime);base64,\(data.base64EncodedString())"
        }
        let rep = NSBitmapImageRep(data: data)
            ?? NSImage(data: data)?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        guard let png = rep?.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}

/// WKWebView handles file drops itself, but only ever exposes them to the page
/// as File objects with no path - so intercept image drops before WebKit sees
/// them and load them natively instead, where the source folder is knowable.
final class DropWebView: WKWebView {
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes(registeredDraggedTypes + [.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func droppedImage(_ sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]
        ) as? [URL]
        return urls?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedImage(sender) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedImage(sender) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppedImage(sender) != nil ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = droppedImage(sender) {
            PhotoBridge.shared.open(url)
            return true
        }
        return super.performDragOperation(sender)
    }
}

struct WebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = DropWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Let the window's glass material show through the page
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        PhotoBridge.shared.webView = webView
        if let url = Bundle.main.url(forResource: "Croppenheimer", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            PhotoBridge.shared.flushPending()
        }

        // The page triggers downloads via <a download> pointing at a blob: URL.
        // WKWebView surfaces that as a navigation action with
        // shouldPerformDownload set; route it through WKDownload into a save panel.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        }

        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.directoryURL = PhotoBridge.shared.sourceDirectory
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.begin { result in
                guard result == .OK, let url = panel.url else {
                    completionHandler(nil)
                    return
                }
                // WKDownload refuses to overwrite; the panel already confirmed replacement.
                try? FileManager.default.removeItem(at: url)
                completionHandler(url)
            }
        }

        // <input type=file> does nothing in a WKWebView unless the host app
        // presents the panel. Doing it here also tells us the source folder.
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.allowedContentTypes = [.image]
            panel.directoryURL = PhotoBridge.shared.sourceDirectory
            panel.begin { result in
                guard result == .OK, let first = panel.urls.first else {
                    completionHandler(nil)
                    return
                }
                PhotoBridge.shared.noteSource(first)
                completionHandler(panel.urls)
            }
        }
    }
}
