import SwiftUI
import WebKit
import AppKit

struct WebView: NSViewRepresentable {
    let webView: WKWebView
    let onDrop: (String) -> Void
    let onTargetedChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrop: onDrop, onTargetedChange: onTargetedChange)
    }

    func makeNSView(context: Context) -> WebContainerView {
        let container = WebContainerView(webView: webView, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: WebContainerView, context: Context) {
        nsView.updateCoordinator(context.coordinator)
        nsView.updateWebView(webView)
    }

    final class Coordinator {
        let onDrop: (String) -> Void
        let onTargetedChange: (Bool) -> Void

        init(onDrop: @escaping (String) -> Void, onTargetedChange: @escaping (Bool) -> Void) {
            self.onDrop = onDrop
            self.onTargetedChange = onTargetedChange
        }
    }
}

final class WebContainerView: NSView {
    private(set) var webView: WKWebView
    private let dropView = DropReceiverView()

    init(webView: WKWebView, coordinator: WebView.Coordinator) {
        self.webView = webView
        super.init(frame: .zero)

        wantsLayer = true

        webView.translatesAutoresizingMaskIntoConstraints = false
        dropView.translatesAutoresizingMaskIntoConstraints = false
        dropView.coordinator = coordinator

        addSubview(webView)
        addSubview(dropView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dropView.topAnchor.constraint(equalTo: topAnchor),
            dropView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateCoordinator(_ coordinator: WebView.Coordinator) {
        dropView.coordinator = coordinator
    }

    func updateWebView(_ webView: WKWebView) {
        guard self.webView !== webView else { return }
        self.webView.removeFromSuperview()
        self.webView = webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView, positioned: .below, relativeTo: dropView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class DropReceiverView: NSView {
    weak var coordinator: WebView.Coordinator?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.URL, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.URL, .string])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedURLString(from: sender.draggingPasteboard) != nil else {
            coordinator?.onTargetedChange(false)
            return []
        }
        coordinator?.onTargetedChange(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        coordinator?.onTargetedChange(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppedURLString(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let droppedURL = droppedURLString(from: sender.draggingPasteboard) else {
            coordinator?.onTargetedChange(false)
            return false
        }
        coordinator?.onTargetedChange(false)
        coordinator?.onDrop(droppedURL)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        coordinator?.onTargetedChange(false)
    }

    private func droppedURLString(from pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first {
            return url.absoluteString
        }
        if let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String],
           let string = strings.first {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
}
