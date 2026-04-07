import SwiftUI
import WebKit
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
    @State private var contentOpacity: Double = 1.0
    @State private var isFillPlayerWindowEnabled = false
    @State private var hoverMonitorTimer: Timer?
    @State private var historyNoticeClearTask: DispatchWorkItem?
    private let playerWindowIdentifier = NSUserInterfaceItemIdentifier("YouTubePlayerWindow")
    private let playerWindowFrameKey = "playerWindowFrame"
    private let alwaysOnTopLevel = NSWindow.Level.statusBar
    private let alwaysOnTopBehaviors: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    private let lastURLKey = "lastURL"
    private let lastPlaybackPositionsKey = "lastPlaybackPositions"
    private let initialSavedURL: URL?
    @State private var playbackPositions: [String: Double]
    @State private var currentVideoID: String?
    @State private var pendingInitialURL: URL?
    @State private var window: NSWindow?
    private let windowCoordinator = PlayerWindowCoordinator()

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
                    const titleNode = document.querySelector('ytd-watch-metadata h1 yt-formatted-string');
                    const title = (titleNode && titleNode.textContent ? titleNode.textContent : document.title || '').trim();
                    handler.postMessage({ videoId: videoId, currentTime: video.currentTime || 0, title: title });
                };

                window.nativePostPlaybackProgress = postProgress;

                const install = () => {
                    postProgress();
                    setInterval(postProgress, 1000);
                    const video = document.querySelector('video');
                    if (video) {
                        ['pause', 'seeking', 'seeked', 'ended'].forEach((eventName) => {
                            video.addEventListener(eventName, postProgress);
                        });
                    }
                    document.addEventListener('visibilitychange', postProgress);
                    window.addEventListener('pagehide', postProgress);
                    window.addEventListener('beforeunload', postProgress);
                    window.addEventListener('yt-navigate-start', postProgress);
                    window.addEventListener('yt-navigate-finish', postProgress);
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

        let fillPlayerWindowScript = WKUserScript(
            source: """
            (function() {
                const storageKey = 'nativeFillPlayerWindow';
                const transparentPlayerStorageKey = 'nativeTransparentPlayerChrome';
                const styleId = 'native-fill-player-window-style';
                const transparentStyleId = 'native-transparent-player-style';
                const className = 'native-fill-player-window';
                const transparentClassName = 'native-transparent-player';
                const css = `
                html.${className}, body.${className} {
                    overflow: hidden !important;
                    background: #000 !important;
                    --ytd-masthead-height: 0px !important;
                    --ytd-toolbar-height: 0px !important;
                }
                html.${className} ytd-masthead,
                body.${className} ytd-masthead,
                html.${className} #masthead-container,
                body.${className} #masthead-container,
                html.${className} tp-yt-app-header-layout,
                body.${className} tp-yt-app-header-layout {
                    display: none !important;
                }
                html.${className} #secondary,
                body.${className} #secondary,
                html.${className} #below,
                body.${className} #below,
                html.${className} #related,
                body.${className} #related,
                html.${className} #comments,
                body.${className} #comments,
                html.${className} ytd-comments,
                body.${className} ytd-comments,
                html.${className} #chat,
                body.${className} #chat {
                    display: none !important;
                }
                html.${className} ytd-app,
                body.${className} ytd-app,
                html.${className} #page-manager,
                body.${className} #page-manager,
                html.${className} ytd-watch-flexy,
                body.${className} ytd-watch-flexy,
                html.${className} #primary,
                body.${className} #primary,
                html.${className} #primary-inner,
                body.${className} #primary-inner,
                html.${className} #columns,
                body.${className} #columns,
                html.${className} #contents,
                body.${className} #contents {
                    margin-top: 0 !important;
                    padding-top: 0 !important;
                    top: 0 !important;
                }
                html.${className} ytd-watch-flexy,
                body.${className} ytd-watch-flexy {
                    min-width: 100vw !important;
                    min-height: 100vh !important;
                    background: #000 !important;
                }
                html.${className} #player-theater-container,
                body.${className} #player-theater-container,
                html.${className} #full-bleed-container,
                body.${className} #full-bleed-container,
                html.${className} #player,
                body.${className} #player,
                html.${className} ytd-player,
                body.${className} ytd-player,
                html.${className} #movie_player,
                body.${className} #movie_player,
                html.${className} .html5-video-container,
                body.${className} .html5-video-container,
                html.${className} video,
                body.${className} video {
                    width: 100% !important;
                    height: 100% !important;
                    max-width: none !important;
                    max-height: none !important;
                }
                html.${className} #player-theater-container,
                body.${className} #player-theater-container,
                html.${className} #full-bleed-container,
                body.${className} #full-bleed-container,
                html.${className} #player,
                body.${className} #player,
                html.${className} ytd-player,
                body.${className} ytd-player,
                html.${className} #movie_player,
                body.${className} #movie_player {
                    position: relative !important;
                    inset: auto !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    background: #000 !important;
                }
                `;
                const transparentCss = `
                html.${transparentClassName}, body.${transparentClassName},
                html.${transparentClassName} ytd-app, body.${transparentClassName} ytd-app,
                html.${transparentClassName} #page-manager, body.${transparentClassName} #page-manager,
                html.${transparentClassName} ytd-watch-flexy, body.${transparentClassName} ytd-watch-flexy,
                html.${transparentClassName} #player, body.${transparentClassName} #player,
                html.${transparentClassName} ytd-player, body.${transparentClassName} ytd-player,
                html.${transparentClassName} #movie_player, body.${transparentClassName} #movie_player,
                html.${transparentClassName} .html5-video-player, body.${transparentClassName} .html5-video-player,
                html.${transparentClassName} .html5-video-container, body.${transparentClassName} .html5-video-container,
                html.${transparentClassName} .ytp-gradient-top, body.${transparentClassName} .ytp-gradient-top,
                html.${transparentClassName} .ytp-gradient-bottom, body.${transparentClassName} .ytp-gradient-bottom {
                    background: transparent !important;
                    box-shadow: none !important;
                }
                `;

                function ensureStyle() {
                    if (document.getElementById(styleId)) { return; }
                    const style = document.createElement('style');
                    style.id = styleId;
                    style.textContent = css;
                    (document.head || document.documentElement).appendChild(style);
                }

                function ensureTransparentStyle() {
                    if (document.getElementById(transparentStyleId)) { return; }
                    const style = document.createElement('style');
                    style.id = transparentStyleId;
                    style.textContent = transparentCss;
                    (document.head || document.documentElement).appendChild(style);
                }

                function applyMode(enabled) {
                    ensureStyle();
                    const root = document.documentElement;
                    const body = document.body;
                    if (!root) { return; }
                    root.classList.toggle(className, enabled);
                    if (body) { body.classList.toggle(className, enabled); }
                    if (enabled) {
                        const moviePlayer = document.getElementById('movie_player');
                        if (moviePlayer && typeof moviePlayer.toggleTheaterMode === 'function') {
                            try {
                                const isTheater = moviePlayer.classList.contains('ytp-size-button-large');
                                if (!isTheater) { moviePlayer.toggleTheaterMode(); }
                            } catch (e) {}
                        }
                        if (moviePlayer && typeof moviePlayer.setSize === 'function') {
                            moviePlayer.setSize(window.innerWidth, window.innerHeight);
                        }
                    }
                }

                function applyTransparentPlayerMode(enabled) {
                    ensureTransparentStyle();
                    const root = document.documentElement;
                    const body = document.body;
                    if (!root) { return; }
                    root.classList.toggle(transparentClassName, enabled);
                    if (body) { body.classList.toggle(transparentClassName, enabled); }
                }

                function syncFromStorage() {
                    applyMode(localStorage.getItem(storageKey) === '1');
                    applyTransparentPlayerMode(localStorage.getItem(transparentPlayerStorageKey) === '1');
                }

                window.setNativeFillPlayerWindow = function(enabled) {
                    localStorage.setItem(storageKey, enabled ? '1' : '0');
                    applyMode(enabled);
                    window.setTimeout(syncFromStorage, 150);
                    window.setTimeout(syncFromStorage, 600);
                    window.setTimeout(syncFromStorage, 1200);
                };

                window.setNativeTransparentPlayerMode = function(enabled) {
                    localStorage.setItem(transparentPlayerStorageKey, enabled ? '1' : '0');
                    applyTransparentPlayerMode(enabled);
                    window.setTimeout(syncFromStorage, 150);
                };

                syncFromStorage();
                document.addEventListener('DOMContentLoaded', syncFromStorage, { once: false });
                window.addEventListener('resize', syncFromStorage);
                window.addEventListener('yt-navigate-finish', syncFromStorage);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        config.userContentController.addUserScript(script)
        config.userContentController.addUserScript(progressTrackingScript)
        config.userContentController.addUserScript(fillPlayerWindowScript)
        config.userContentController.add(scriptHandler, name: "videoProgress")

        initialSavedURL = UserDefaults.standard.string(forKey: lastURLKey).flatMap { URL(string: $0) }
        let savedPositions = UserDefaults.standard.dictionary(forKey: lastPlaybackPositionsKey) as? [String: Double] ?? [:]
        _playbackPositions = State(initialValue: savedPositions)
        _currentVideoID = State(initialValue: nil)
        _pendingInitialURL = State(initialValue: initialSavedURL)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        wv.setValue(false, forKey: "drawsBackground")
        scriptHandler.onPageReady = { [weak wv] in
            DispatchQueue.main.async {
                guard let wv else { return }
                let enabled = UserDefaults.standard.bool(forKey: "settings.fillPlayerWindowEnabled")
                wv.evaluateJavaScript("window.setNativeFillPlayerWindow && window.setNativeFillPlayerWindow(\(enabled ? "true" : "false"));")
            }
        }
        wv.navigationDelegate = scriptHandler

        _webView = State(initialValue: wv)

        if initialSavedURL != nil {
            _statusMessage = State(initialValue: "")
        }
    }

    var body: some View {
        ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)

            WebView(
                webView: webView,
                onDrop: { droppedURL in
                    loadYouTubeURL(droppedURL)
                },
                onTargetedChange: { isTargeted in
                    DispatchQueue.main.async {
                        isDropTargeted = isTargeted
                    }
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(contentOpacity)

            VStack {
                HStack {
                    if isFillPlayerWindowEnabled {
                        Button {
                            setFillPlayerWindow(to: false)
                            AppSettings.shared.fillPlayerWindowEnabled = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(6)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 10)
            .padding(.leading, 10)

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

            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.55))

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.red.opacity(0.95), Color.white.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )

                    VStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(Color.white, Color.red.opacity(0.95))

                        Text("Drop YouTube URL Here")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)

                        Text("Drag a link from your browser address bar to start playback")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                }
                .padding(26)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            handleHoverChange(hovering)
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
        .onReceive(NotificationCenter.default.publisher(for: .setFillPlayerWindow)) { notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                setFillPlayerWindow(to: enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setLockAspectRatio16x9)) { notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                setLockAspectRatio16x9(to: enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecentVideo)) { notification in
            guard let videoID = notification.userInfo?["videoID"] as? String else { return }
            let time = notification.userInfo?["time"] as? Double ?? 0
            playRecentVideo(videoID: videoID, startTime: time)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            persistCurrentPlaybackPosition()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reassertAlwaysOnTopState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let eventWindow = notification.object as? NSWindow, isPlayerWindow(eventWindow) else { return }
            reassertAlwaysOnTopState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let closingWindow = notification.object as? NSWindow, closingWindow == getWindow() else { return }
            persistLastOpenedVideoFallback()
            pauseAndPersistCurrentPlayback()
            window = nil
        }
        .onAppear {
            // Set up the progress callback
            scriptHandler.onProgress = { videoId, time, title in
                updatePlaybackPosition(videoID: videoId, time: time, title: title)
            }

            scheduleWindowSetup()
            // Sync initial state with settings
            isAlwaysOnTop = settings.alwaysOnTopEnabled
            setAlwaysOnTop(to: settings.alwaysOnTopEnabled)
            setEightyTransparency(to: settings.eightyTransparencyEnabled)
            setHoverTransparency(to: settings.hoverTransparencyEnabled)
            setFillPlayerWindow(to: settings.fillPlayerWindowEnabled)
            setLockAspectRatio16x9(to: settings.lockAspectRatio16x9Enabled)
            if let url = pendingInitialURL {
                pendingInitialURL = nil
                loadYouTubeURL(url.absoluteString, rememberAsLast: false)
            }
        }
        .onDisappear {
            persistLastOpenedVideoFallback()
            hoverMonitorTimer?.invalidate()
            hoverMonitorTimer = nil
        }
    }

    func loadYouTubeURL(_ urlString: String, rememberAsLast: Bool = true) {
        if let videoID = URLHelper.extractVideoID(from: urlString) {
            let savedTime = playbackPositions[videoID]
            let startTime = (savedTime ?? 0) >= 1 ? Int(savedTime ?? 0) : nil
            loadVideo(videoID: videoID, startTime: startTime.map(Double.init) ?? 0, rememberAsLast: rememberAsLast)
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

    func playRecentVideo(videoID: String, startTime: Double) {
        loadVideo(videoID: videoID, startTime: startTime, rememberAsLast: true)
    }

    func loadVideo(videoID: String, startTime: Double, rememberAsLast: Bool) {
        if rememberAsLast {
            settings.allowRecording(videoID: videoID)
        }
        let start = adjustedResumeStartTime(from: startTime)
        let watchURL = URLHelper.makeWatchURL(videoID: videoID, startTime: start > 0 ? start : nil)
        DispatchQueue.main.async {
            if loadedVideoID() == videoID {
                currentVideoID = videoID
                applyHistoryNotice(historyEntry(for: videoID))
                if rememberAsLast {
                    UserDefaults.standard.set(watchURL, forKey: lastURLKey)
                }
                return
            }
            if let url = URL(string: watchURL) {
                let historyEntry = historyEntry(for: videoID)
                currentVideoID = videoID
                webView.load(URLRequest(url: url))
                applyHistoryNotice(historyEntry)
                if rememberAsLast {
                    UserDefaults.standard.set(watchURL, forKey: lastURLKey)
                }
            }
        }
    }

    private func adjustedResumeStartTime(from startTime: Double) -> Int {
        let roundedStart = Int(startTime.rounded())
        guard roundedStart > 0 else { return 0 }
        return max(0, roundedStart - 5)
    }

    func historyEntry(for videoID: String) -> RecentVideoItem? {
        settings.watchHistoryVideos.first(where: { $0.videoID == videoID })
            ?? settings.recentVideos.first(where: { $0.videoID == videoID })
    }

    func applyHistoryNotice(_ video: RecentVideoItem?) {
        historyNoticeClearTask?.cancel()
        historyNoticeClearTask = nil
        guard let video else {
            statusMessage = ""
            return
        }
        if video.isThumbsDown {
            showHistoryAlert(
                title: "This video was marked thumbs down",
                message: "\"\(video.title)\" is in your history as a thumbs-down video."
            )
            statusMessage = "History note: thumbs down"
            return
        }
        if video.watchLaterStars > 0 {
            let starLabel = video.watchLaterStars == 1 ? "star" : "stars"
            showTemporaryHistoryNotice("Watched earlier: rated \(video.watchLaterStars) \(starLabel)", duration: 180)
            return
        }
        statusMessage = ""
    }

    private func showTemporaryHistoryNotice(_ message: String, duration: TimeInterval) {
        statusMessage = message
        let clearTask = DispatchWorkItem {
            if statusMessage == message {
                statusMessage = ""
            }
            historyNoticeClearTask = nil
        }
        historyNoticeClearTask = clearTask
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: clearTask)
    }

    func showHistoryAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
        contentOpacity = 1.0
        window.ignoresMouseEvents = false
        applyAlwaysOnTopState(window)
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
                // Mouse over: hide content completely and pass clicks through
                contentOpacity = 0.0
                window.ignoresMouseEvents = true
                applyTransparentWindowAppearance(window, isFullyTransparent: true)
                ensureWindowFront(window) // keep app active so menus remain usable
            } else {
                // Mouse away: make content opaque and clickable
                contentOpacity = 1.0
                window.ignoresMouseEvents = false
                applyTransparentWindowAppearance(window, isFullyTransparent: false)
                ensureWindowFront(window)
            }
            applyTransparentSurfaceMode()
        }
    }

    private func startHoverMonitor(for window: NSWindow) {
        hoverMonitorTimer?.invalidate()
        hoverMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            DispatchQueue.main.async {
                updateHoverStateFromMouseLocation(window: window)
            }
        }
        if let hoverMonitorTimer {
            RunLoop.main.add(hoverMonitorTimer, forMode: .common)
        }
    }

    private func stopHoverMonitor() {
        hoverMonitorTimer?.invalidate()
        hoverMonitorTimer = nil
    }

    private func updateHoverStateFromMouseLocation(window: NSWindow) {
        guard isTransparent else { return }
        let mouseLocation = NSEvent.mouseLocation
        let contentRectInScreen = window.convertToScreen(window.contentLayoutRect)
        let hoveringNow = contentRectInScreen.contains(mouseLocation)
        if hoveringNow != isHovering {
            isHovering = hoveringNow
            handleHoverChange(hoveringNow)
        } else if !hoveringNow, window.ignoresMouseEvents {
            contentOpacity = 1.0
            window.ignoresMouseEvents = false
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
                contentOpacity = 1.0
                window.ignoresMouseEvents = false
                ensureWindowFront(window)
            } else {
                // Always opaque and clickable
                contentOpacity = 1.0
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
            let newOpacity: Double = isDimmed ? 0.25 : 1.0
            contentOpacity = newOpacity
            window.ignoresMouseEvents = false
            applyTransparentWindowAppearance(window, isFullyTransparent: newOpacity == 0)
            applyTransparentSurfaceMode()

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

            let newOpacity: Double = enabled ? 0.2 : 1.0
            contentOpacity = newOpacity
            window.ignoresMouseEvents = false
            applyTransparentWindowAppearance(window, isFullyTransparent: newOpacity == 0)
            applyTransparentSurfaceMode()
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
                startHoverMonitor(for: window)
                updateHoverStateFromMouseLocation(window: window)
                contentOpacity = isHovering ? 0.0 : 1.0
                window.ignoresMouseEvents = isHovering
                applyTransparentWindowAppearance(window, isFullyTransparent: isHovering)
                statusMessage = "Hover mode enabled"
            } else {
                stopHoverMonitor()
                isHovering = false
                contentOpacity = 1.0
                window.ignoresMouseEvents = false
                applyTransparentWindowAppearance(window, isFullyTransparent: false)
                statusMessage = "Hover mode disabled"
            }
            applyTransparentSurfaceMode()
            ensureWindowFront(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "Hover mode enabled" || statusMessage == "Hover mode disabled" {
                    statusMessage = ""
                }
            }
        }
    }

    func setFillPlayerWindow(to enabled: Bool) {
        isFillPlayerWindowEnabled = enabled
        DispatchQueue.main.async {
            let script = "window.setNativeFillPlayerWindow && window.setNativeFillPlayerWindow(\(enabled ? "true" : "false"));"
            webView.evaluateJavaScript(script)
            statusMessage = enabled ? "Fill player window enabled" : "Fill player window disabled"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "Fill player window enabled" || statusMessage == "Fill player window disabled" {
                    statusMessage = ""
                }
            }
        }
    }

    func setLockAspectRatio16x9(to enabled: Bool) {
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
            windowCoordinator.lockAspectRatio16x9 = enabled
            if enabled {
                windowCoordinator.applyLockedAspectRatio(to: window)
            }
            statusMessage = enabled ? "16:9 resize lock enabled" : "16:9 resize lock disabled"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "16:9 resize lock enabled" || statusMessage == "16:9 resize lock disabled" {
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

    private func updatePlaybackPosition(videoID: String, time: Double, title: String?) {
        DispatchQueue.main.async {
            currentVideoID = videoID
            playbackPositions[videoID] = time
            UserDefaults.standard.set(playbackPositions, forKey: lastPlaybackPositionsKey)
            let lastWatchURL = URLHelper.makeWatchURL(videoID: videoID, startTime: Optional<Int>.none)
            UserDefaults.standard.set(lastWatchURL, forKey: lastURLKey)
            AppSettings.shared.recordRecentVideo(videoID: videoID, title: title, position: time)
        }
    }

    private func activeVideoID() -> String? {
        currentVideoID ?? webView.url.flatMap { URLHelper.extractVideoID(from: $0.absoluteString) }
    }

    private func loadedVideoID() -> String? {
        webView.url.flatMap { URLHelper.extractVideoID(from: $0.absoluteString) }
    }

    private func persistCurrentPlaybackPosition() {
        let script = "window.nativePostPlaybackProgress && window.nativePostPlaybackProgress();"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script)
        }
    }

    private func persistLastOpenedVideoFallback() {
        guard let videoID = activeVideoID() else { return }
        let savedTime = playbackPositions[videoID].flatMap { $0 >= 1 ? Int($0.rounded()) : nil }
        let watchURL = URLHelper.makeWatchURL(videoID: videoID, startTime: savedTime)
        UserDefaults.standard.set(watchURL, forKey: lastURLKey)
    }

    private func pauseAndPersistCurrentPlayback() {
        let script = """
        (function() {
            window.nativePostPlaybackProgress && window.nativePostPlaybackProgress();
            const video = document.querySelector('video');
            if (video) {
                video.pause();
                video.currentTime = video.currentTime || 0;
            }
        })();
        """
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script)
        }
    }

    private func applyTransparentSurfaceMode() {
        let enabled = contentOpacity < 1.0
        let script = "window.setNativeTransparentPlayerMode && window.setNativeTransparentPlayerMode(\(enabled ? "true" : "false"));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script)
        }
    }

    private func applyTransparentWindowAppearance(_ window: NSWindow, isFullyTransparent: Bool) {
        window.hasShadow = !isFullyTransparent
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
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .hidden
            window.toolbarStyle = .unifiedCompact
            window.styleMask.remove(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = false
            window.delegate = windowCoordinator
            restoreWindowFrameIfNeeded(window)
            startPersistingWindowFrame(window)

            // Set collection behavior once during initial setup
            // This makes the window appear on all spaces and move with active space
            window.collectionBehavior = alwaysOnTopBehaviors
        }

        windowCoordinator.lockAspectRatio16x9 = settings.lockAspectRatio16x9Enabled
        isAlwaysOnTop = settings.alwaysOnTopEnabled
        applyAlwaysOnTopState(window)
    }

    private func restoreWindowFrameIfNeeded(_ window: NSWindow) {
        guard let frameString = UserDefaults.standard.string(forKey: playerWindowFrameKey) else { return }
        let frame = NSRectFromString(frameString)
        guard frame.width > 0, frame.height > 0 else { return }
        window.setFrame(frame, display: false)
    }

    private func startPersistingWindowFrame(_ window: NSWindow) {
        windowCoordinator.onFrameChanged = { frame in
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: playerWindowFrameKey)
        }
        windowCoordinator.persistFrame(window.frame)
    }

    private func applyAlwaysOnTopState(_ window: NSWindow) {
        guard isPlayerWindow(window), isWindowReadyForLevelChanges(window) else { return }

        // Dispatch to next run loop to avoid modifying window during layout
        DispatchQueue.main.async {
            // Just use window level - don't modify collection behavior
            let targetLevel: NSWindow.Level = self.isAlwaysOnTop ? self.alwaysOnTopLevel : .normal
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
        if window.level != alwaysOnTopLevel {
            window.level = alwaysOnTopLevel
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

final class YouTubeScriptMessageHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onProgress: ((String, Double, String?) -> Void)?
    var onPageReady: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "videoProgress",
              let body = message.body as? [String: Any],
              let videoId = body["videoId"] as? String,
              let currentTime = body["currentTime"] as? Double else { return }
        let title = body["title"] as? String
        onProgress?(videoId, currentTime, title)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onPageReady?()
    }
}

final class PlayerWindowCoordinator: NSObject, NSWindowDelegate {
    var lockAspectRatio16x9 = false
    var onFrameChanged: ((NSRect) -> Void)?
    private var isAdjustingFrame = false

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if lockAspectRatio16x9 {
            applyLockedAspectRatio(to: window)
        }
        persistFrame(window.frame)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        persistFrame(window.frame)
    }

    func persistFrame(_ frame: NSRect) {
        onFrameChanged?(frame)
    }

    func applyLockedAspectRatio(to window: NSWindow) {
        guard lockAspectRatio16x9, !isAdjustingFrame else { return }

        let contentRect = window.contentRect(forFrameRect: window.frame)
        guard contentRect.width > 0 else { return }

        let targetContentHeight = round(contentRect.width * 9.0 / 16.0)
        guard abs(contentRect.height - targetContentHeight) > 1 else { return }

        let adjustedContentRect = NSRect(
            origin: contentRect.origin,
            size: NSSize(width: contentRect.width, height: targetContentHeight)
        )
        let adjustedFrameSize = window.frameRect(forContentRect: adjustedContentRect).size
        var adjustedFrame = window.frame
        adjustedFrame.origin.y += adjustedFrame.height - adjustedFrameSize.height
        adjustedFrame.size = adjustedFrameSize

        isAdjustingFrame = true
        DispatchQueue.main.async {
            window.setFrame(adjustedFrame, display: true)
            self.isAdjustingFrame = false
        }
    }
}
