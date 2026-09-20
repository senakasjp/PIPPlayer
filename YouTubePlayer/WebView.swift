import SwiftUI
import WebKit
import AppKit

struct PlayerWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct WebView: NSViewRepresentable {
    let webView: WKWebView
    var nativeVideoView: NSView? = nil
    let onDrop: (String) -> Void
    let onTargetedChange: (Bool) -> Void
    var onPlaybackKey: (UInt16) -> Bool = { _ in false }

    static func receiveDrop(_ providers: [NSItemProvider], onDrop: @escaping (String) -> Void) -> Bool {
        let types = ["public.file-url", "public.url", "public.utf8-plain-text"]
        for provider in providers {
            guard let type = types.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else { continue }
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                guard error == nil else { return }
                let input: String?
                if let url = item as? URL {
                    input = url.absoluteString
                } else if let data = item as? Data {
                    input = String(data: data, encoding: .utf8)
                } else {
                    input = item as? String
                }
                guard let input, StreamingProviderRegistry.shared.resolve(input) != nil else { return }
                DispatchQueue.main.async { onDrop(input) }
            }
            return true
        }
        return false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrop: onDrop, onTargetedChange: onTargetedChange)
    }

    func makeNSView(context: Context) -> WebContainerView {
        let container = WebContainerView(webView: webView, coordinator: context.coordinator)
        container.updateNativeVideoView(nativeVideoView)
        container.onPlaybackKey = onPlaybackKey
        return container
    }

    func updateNSView(_ nsView: WebContainerView, context: Context) {
        nsView.updateCoordinator(context.coordinator)
        nsView.updateWebView(webView)
        nsView.updateNativeVideoView(nativeVideoView)
        nsView.onPlaybackKey = onPlaybackKey
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
    private var nativeVideoView: NSView?
    var onPlaybackKey: (UInt16) -> Bool = { _ in false }
    private var keyboardMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        guard window != nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window,
                  window.isKeyWindow, event.window === window,
                  window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSTextView),
                  !(window.firstResponder is NSSlider),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  [UInt16(49), 123, 124].contains(event.keyCode) else { return event }
            if event.keyCode == 49 && event.isARepeat { return nil }
            return self.onPlaybackKey(event.keyCode) ? nil : event
        }
    }

    deinit {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

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

    func updateNativeVideoView(_ view: NSView?) {
        guard nativeVideoView !== view else { return }
        nativeVideoView?.removeFromSuperview()
        nativeVideoView = view
        webView.isHidden = view != nil
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .below, relativeTo: dropView)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL, .string])
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
        let onDrop = coordinator?.onDrop
        DispatchQueue.main.async {
            onDrop?(droppedURL)
        }
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        coordinator?.onTargetedChange(false)
    }

    func droppedURLString(from pasteboard: NSPasteboard) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first(where: { StreamingProviderRegistry.shared.resolve($0.absoluteString) != nil }) {
            return url.absoluteString
        }
        if let strings = pasteboard.readObjects(forClasses: [NSString.self]) as? [String],
           let string = strings.first {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard StreamingProviderRegistry.shared.resolve(trimmed) != nil else { return nil }
            return trimmed
        }
        return nil
    }
}
