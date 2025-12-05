import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var webView: WKWebView
    private let scriptHandler: YouTubeScriptMessageHandler
    @State private var isDropTargeted = false
    @State private var statusMessage = "Drop a YouTube URL to play"
    @State private var isTransparent = true
    @State private var isAlwaysOnTop = true
    @State private var isEightyTransparency = false
    @State private var isDimmed = false
    @State private var isHovering = false
    private let playerWindowIdentifier = NSUserInterfaceItemIdentifier("YouTubePlayerWindow")
    private let alwaysOnTopBehaviors: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    private let lastURLKey = "lastURL"
    private let lastPlaybackPositionsKey = "lastPlaybackPositions"
    private let initialSavedURL: URL?
    @State private var playbackPositions: [String: Double]
    @State private var pendingInitialURL: URL?
    @State private var window: NSWindow?

    init() {
        scriptHandler = YouTubeScriptMessageHandler()
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

        let progressTrackingScript = WKUserScript(
            source: """
            (function() {
                const handler = window.webkit?.messageHandlers?.videoProgress;
                if (!handler) { return; }

                const postProgress = () => {
                    const video = document.querySelector('video');
                    if (!video) { return; }
                    const params = new URLSearchParams(window.location.search);
                    const videoId = params.get('v') || '';
                    if (!videoId) { return; }
                    handler.postMessage({ videoId: videoId, currentTime: video.currentTime || 0 });
                };

                const install = () => {
                    postProgress();
                    setInterval(postProgress, 1000);
                };

                if (document.readyState === 'complete' || document.readyState === 'interactive') {
                    install();
                } else {
                    document.addEventListener('DOMContentLoaded', install, { once: true });
                }
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        config.userContentController.addUserScript(script)
        config.userContentController.addUserScript(progressTrackingScript)
        config.userContentController.add(scriptHandler, name: "videoProgress")

        initialSavedURL = UserDefaults.standard.string(forKey: lastURLKey).flatMap { URL(string: $0) }
        let savedPositions = UserDefaults.standard.dictionary(forKey: lastPlaybackPositionsKey) as? [String: Double] ?? [:]
        _playbackPositions = State(initialValue: savedPositions)
        _pendingInitialURL = State(initialValue: initialSavedURL)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        _webView = State(initialValue: wv)

        if initialSavedURL != nil {
            _statusMessage = State(initialValue: "")
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
            // Set up the progress callback
            scriptHandler.onProgress = { videoId, time in
                DispatchQueue.main.async {
                    var positions = UserDefaults.standard.dictionary(forKey: lastPlaybackPositionsKey) as? [String: Double] ?? [:]
                    positions[videoId] = time
                    UserDefaults.standard.set(positions, forKey: lastPlaybackPositionsKey)
                }
            }

            scheduleWindowSetup()
            // Sync initial state with settings
            applyAlwaysOnTopWhenReady()
            setEightyTransparency(to: settings.eightyTransparencyEnabled)
            setHoverTransparency(to: settings.hoverTransparencyEnabled)
            if let url = pendingInitialURL {
                pendingInitialURL = nil
                loadYouTubeURL(url.absoluteString, rememberAsLast: false)
            }
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

    func loadYouTubeURL(_ urlString: String, rememberAsLast: Bool = true) {
        if let videoID = URLHelper.extractVideoID(from: urlString) {
            let savedTime = playbackPositions[videoID]
            let startTime = (savedTime ?? 0) >= 1 ? Int(savedTime ?? 0) : nil
            let watchURL = URLHelper.makeWatchURL(videoID: videoID, startTime: startTime)
            DispatchQueue.main.async {
                if let url = URL(string: watchURL) {
                    webView.load(URLRequest(url: url))
                    statusMessage = ""
                    if rememberAsLast {
                        UserDefaults.standard.set(watchURL, forKey: lastURLKey)
                    }
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
        if !Thread.isMainThread {
            DispatchQueue.main.async { configureWindow() }
            return
        }
        guard let window = getWindowIfReady() else {
            scheduleWindowSetup()
            return
        }
        applyWindowConfiguration(window)

        // Start opaque and clickable
        window.alphaValue = 1.0
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func scheduleWindowSetup(retryCount: Int = 10) {
        guard retryCount > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if getWindowIfReady() != nil {
                configureWindow()
            } else {
                scheduleWindowSetup(retryCount: retryCount - 1)
            }
        }
    }

    func handleHoverChange(_ hovering: Bool) {
        guard isTransparent else { return }
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
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

    func toggleTransparency() {
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
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

    func setAlwaysOnTop(to enabled: Bool) {
        isAlwaysOnTop = enabled
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
            applyAlwaysOnTopState(window)
            if enabled { ensureWindowFront(window) }
            statusMessage = enabled ? "Always on top enabled" : "Always on top disabled"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "Always on top enabled" || statusMessage == "Always on top disabled" {
                    statusMessage = ""
                }
            }
        }
    }

    func toggleOpacity() {
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
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
            guard let window = getWindow() else { return }
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
            guard let window = getWindow() else { return }
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
        applyAlwaysOnTopState(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func updatePlaybackPosition(videoID: String, time: Double) {
        DispatchQueue.main.async {
            playbackPositions[videoID] = time
            UserDefaults.standard.set(playbackPositions, forKey: lastPlaybackPositionsKey)
        }
    }

    private func getWindow() -> NSWindow? {
        if let window {
            return window
        }
        if let found = NSApplication.shared.windows.first(where: { isPlayerWindow($0) }) {
            self.window = found
            return found
        }
        return nil
    }

    private func getWindowIfReady() -> NSWindow? {
        guard let window = getWindow() else { return nil }
        if window.windowNumber <= 0 || !window.isVisible {
            return nil
        }
        return window
    }

    private func applyWindowConfiguration(_ window: NSWindow) {
        guard isPlayerWindow(window) else { return }
        let needsBaseSetup = window.identifier != playerWindowIdentifier
        window.identifier = playerWindowIdentifier

        if needsBaseSetup {
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .black
        }
    }

    private func applyAlwaysOnTopState(_ window: NSWindow) {
        guard isPlayerWindow(window), isWindowReadyForLevelChanges(window) else { return }

        // Dispatch to next run loop to avoid modifying window during layout
        DispatchQueue.main.async {
            // Just use window level - don't modify collection behavior
            let targetLevel: NSWindow.Level = self.isAlwaysOnTop ? .floating : .normal
            if window.level != targetLevel {
                window.level = targetLevel
            }
        }
    }

    private func reassertAlwaysOnTopState() {
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
            applyAlwaysOnTopState(window)
        }
    }

    private func isPlayerWindow(_ window: NSWindow) -> Bool {
        if window.identifier == playerWindowIdentifier { return true }
        let className = String(describing: type(of: window))
        if className.contains("StatusBarWindow") || className.contains("StatusItemWindow") { return false }
        if let contentView = window.contentView {
            let contentClass = String(describing: type(of: contentView))
            if contentClass.contains("Hosting") { return true }
        }
        return window.canBecomeMain
    }

    private func applyAlwaysOnTopLevelAndBehavior(_ window: NSWindow) {
        // Just set window level - collection behavior modification causes crashes
        if window.level != .floating {
            window.level = .floating
        }
    }

    private func isWindowReadyForLevelChanges(_ window: NSWindow) -> Bool {
        let hasNumber = window.windowNumber > 0
        let isVisible = window.isVisible
        let canChangeLevel = window.canBecomeMain || window.canBecomeKey
        let isOnScreen = window.isOnActiveSpace
        return hasNumber && isVisible && canChangeLevel && isOnScreen
    }

    private func applyAlwaysOnTopWhenReady(retries: Int = 20) {
        guard retries > 0 else { return }
        if let window = getWindow(), isWindowReadyForLevelChanges(window) {
            applyAlwaysOnTopState(window)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                applyAlwaysOnTopWhenReady(retries: retries - 1)
            }
        }
    }
}

final class YouTubeScriptMessageHandler: NSObject, WKScriptMessageHandler {
    var onProgress: ((String, Double) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "videoProgress",
              let body = message.body as? [String: Any],
              let videoId = body["videoId"] as? String,
              let currentTime = body["currentTime"] as? Double else { return }
        onProgress?(videoId, currentTime)
    }
}
