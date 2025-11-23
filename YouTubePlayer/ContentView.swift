import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var webView: WKWebView
    @State private var isDropTargeted = false
    @State private var statusMessage = "Drop a YouTube URL to play"
    @State private var isTransparent = true
    @State private var isAlwaysOnTop = true
    @State private var isEightyTransparency = false
    @State private var isDimmed = false
    @State private var isHovering = false
    private let lastURLKey = "lastURL"
    private let initialSavedURL: URL?

    init() {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // CSS to hide scrollbars completely
        let hideScrollbarsCSS = """
        ::-webkit-scrollbar { display: none !important; }
        body { overflow: hidden !important; margin: 0 !important; }
        html { overflow: hidden !important; }
        #masthead-container { display: none !important; }
        ytd-watch-flexy[theater] #player-theater-container.ytd-watch-flexy { max-width: 100% !important; width: 100% !important; }
        """

        let script = WKUserScript(
            source: """
            var style = document.createElement('style');
            style.textContent = '\(hideScrollbarsCSS)';
            document.head.appendChild(style);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )

        config.userContentController.addUserScript(script)

        initialSavedURL = UserDefaults.standard.string(forKey: lastURLKey).flatMap { URL(string: $0) }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        _webView = State(initialValue: wv)

        if let url = initialSavedURL {
            wv.load(URLRequest(url: url))
            statusMessage = ""
        }
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            WebView(webView: webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if statusMessage != "" {
                VStack {
                    Spacer()
                    Text(statusMessage)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding()
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
            handleHoverChange(hovering)
        }
        .onDrop(of: [.url, .text], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openURL)) { _ in
            promptForURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTransparency)) { _ in
            toggleTransparency()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleOpacity)) { _ in
            toggleOpacity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .setAlwaysOnTop)) { notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                setAlwaysOnTop(to: enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setEightyTransparency)) { notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                setEightyTransparency(to: enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setHoverTransparency)) { notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                setHoverTransparency(to: enabled)
            }
        }
        .onAppear {
            configureWindow()
            // Sync initial state with settings
            setAlwaysOnTop(to: settings.alwaysOnTopEnabled)
            setEightyTransparency(to: settings.eightyTransparencyEnabled)
            setHoverTransparency(to: settings.hoverTransparencyEnabled)
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        loadYouTubeURL(url.absoluteString)
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier) { item, error in
                    if let urlString = item as? String {
                        loadYouTubeURL(urlString)
                    }
                }
                return true
            }
        }
        return false
    }

    func loadYouTubeURL(_ urlString: String) {
        if let videoID = URLHelper.extractVideoID(from: urlString) {
            let watchURL = URLHelper.makeWatchURL(videoID: videoID)
            DispatchQueue.main.async {
                if let url = URL(string: watchURL) {
                    webView.load(URLRequest(url: url))
                    statusMessage = ""
                    UserDefaults.standard.set(watchURL, forKey: lastURLKey)
                }
            }
        } else {
            DispatchQueue.main.async {
                statusMessage = "Invalid YouTube URL"
            }
        }
    }

    func promptForURL() {
        let alert = NSAlert()
        alert.messageText = "Open YouTube URL"
        alert.informativeText = "Enter a YouTube video URL:"
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "https://youtube.com/watch?v=..."
        alert.accessoryView = textField

        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let urlString = textField.stringValue
            loadYouTubeURL(urlString)
        }
    }

    func configureWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isOpaque = false
                window.backgroundColor = .black
                window.level = .floating
                // Stay visible across Spaces and alongside fullscreen apps
                window.collectionBehavior.insert(.canJoinAllSpaces)
                window.collectionBehavior.insert(.fullScreenAuxiliary)

                // Start opaque and clickable
                window.alphaValue = 1.0
                window.ignoresMouseEvents = false
                ensureWindowFront(window)
            }
        }
    }

    func handleHoverChange(_ hovering: Bool) {
        guard isTransparent else { return }
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                if hovering {
                    // Mouse over: make transparent and click-through
                    window.alphaValue = 0.1
                    window.ignoresMouseEvents = true
                    ensureWindowFront(window) // keep app active so menus remain usable
                } else {
                    // Mouse away: make opaque and clickable
                    window.alphaValue = 1.0
                    window.ignoresMouseEvents = false
                    ensureWindowFront(window)
                }
            }
        }
    }

    func toggleTransparency() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                isTransparent.toggle()
                settings.hoverTransparencyEnabled = isTransparent
                if isTransparent {
                    // In transparent mode, window responds to hover
                    statusMessage = "Hover mode enabled"
                    // Reset to opaque until hover
                    window.alphaValue = 1.0
                    window.ignoresMouseEvents = false
                    ensureWindowFront(window)
                } else {
                    // Always opaque and clickable
                    window.alphaValue = 1.0
                    window.ignoresMouseEvents = false
                    ensureWindowFront(window)
                    statusMessage = "Hover mode disabled"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if statusMessage == "Hover mode enabled" || statusMessage == "Hover mode disabled" {
                        statusMessage = ""
                    }
                }
            }
        }
    }

    func setAlwaysOnTop(to enabled: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            isAlwaysOnTop = enabled
            if enabled {
                window.collectionBehavior.insert(.canJoinAllSpaces)
                window.collectionBehavior.insert(.fullScreenAuxiliary)
                window.level = .floating
                ensureWindowFront(window)
                statusMessage = "Always on top enabled"
            } else {
                window.level = .normal
                statusMessage = "Always on top disabled"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "Always on top enabled" || statusMessage == "Always on top disabled" {
                    statusMessage = ""
                }
            }
        }
    }

    func toggleOpacity() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            isDimmed.toggle()
            isEightyTransparency = false
            isTransparent = false

            // Dim to 25% or restore to fully opaque; keep clicks enabled
            let newOpacity: CGFloat = isDimmed ? 0.25 : 1.0
            window.alphaValue = newOpacity
            window.ignoresMouseEvents = false

            statusMessage = isDimmed ? "Opacity 25%" : "Opacity 100%"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "Opacity 25%" || statusMessage == "Opacity 100%" {
                    statusMessage = ""
                }
            }
        }
    }

    func setEightyTransparency(to enabled: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            isEightyTransparency = enabled
            isTransparent = false
            isDimmed = false
            settings.hoverTransparencyEnabled = false

            let newOpacity: CGFloat = enabled ? 0.2 : 1.0
            window.alphaValue = newOpacity
            window.ignoresMouseEvents = false
            ensureWindowFront(window)

            statusMessage = enabled ? "Transparency 80% enabled" : "Transparency reset"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "Transparency 80% enabled" || statusMessage == "Transparency reset" {
                    statusMessage = ""
                }
            }
        }
    }

    func setHoverTransparency(to enabled: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            isTransparent = enabled
            if enabled {
                window.alphaValue = isHovering ? 0.1 : 1.0
                window.ignoresMouseEvents = isHovering
                statusMessage = "Hover mode enabled"
            } else {
                window.alphaValue = 1.0
                window.ignoresMouseEvents = false
                statusMessage = "Hover mode disabled"
            }
            ensureWindowFront(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "Hover mode enabled" || statusMessage == "Hover mode disabled" {
                    statusMessage = ""
                }
            }
        }
    }

    private func ensureWindowFront(_ window: NSWindow) {
        window.level = isAlwaysOnTop ? .floating : .normal
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
