import SwiftUI
import WebKit
struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var webView: WKWebView
    private let scriptHandler: YouTubeScriptMessageHandler
    @State private var isDropTargeted = false
    @State private var statusMessage = "Drop a streaming URL to play"
    @State private var isTransparent = true
    @State private var isAlwaysOnTop = true
    @State private var isEightyTransparency = false
    @State private var isDimmed = false
    @State private var isHovering = false
    @State private var contentOpacity: Double = 1.0
    @State private var isFillPlayerWindowEnabled = false
    @State private var hoverMonitorTimer: Timer?
    @State private var historyNoticeClearTask: DispatchWorkItem?
    @State private var statusMessageToken: UUID?
    private let playerWindowIdentifier = NSUserInterfaceItemIdentifier("YouTubePlayerWindow")
    private let playerWindowFrameKey = "playerWindowFrame"
    private let alwaysOnTopLevel = NSWindow.Level.statusBar
    private let alwaysOnTopBehaviors: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    private let lastURLKey = "lastURL"
    private let lastPlaybackPositionsKey = "lastPlaybackPositions"
    private let initialSavedURL: URL?
    @State private var playbackPositions: [String: Double]
    @State private var currentVideoID: String?
    @State private var currentSourceURL: String?
    @State private var pendingInitialURL: URL?
    @State private var window: NSWindow?
    private let windowCoordinator = PlayerWindowCoordinator()

    // IFrame Player API state + native control bar state
    // No default video — player initialises empty to avoid video-specific embed errors
    // on startup. Content loads when the user drops/pastes a URL.
    @State private var playerPageLoaded = false   // player.html has been loaded into the web view
    @State private var playerReady = false        // YT.Player onReady has fired
    @State private var pendingYouTubeID: String?  // video queued before the player was ready
    @State private var pendingYouTubeStart: Double = 0
    @State private var pendingYouTubeAutoplay = false
    @State private var isYouTubeActive = false     // current media is a YouTube IFrame video
    @State private var playerState: Int = -1       // YT.PlayerState: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
    @State private var playerCurrentTime: Double = 0
    @State private var playerDuration: Double = 0
    @State private var playerVolume: Double = 100
    @State private var isScrubbing = false
    @State private var currentVideoTitle: String = ""
    @State private var playlistURLs = UserDefaults.standard.stringArray(forKey: "playlistURLs") ?? []
    @State private var playlistIndex: Int?
    @State private var showingPlaylist = false
    @State private var pendingPlaylistIndex = 0
    @State private var videoZoom = 1.0

    init() {
        scriptHandler = YouTubeScriptMessageHandler()
        let config = WKWebViewConfiguration()
        // player.html is loaded with baseURL https://www.youtube.com so the IFrame
        // API postMessage origin check passes (WKWebView requirement). No custom scheme
        // or file:// load is used: both produce null/opaque origins that YouTube's embed
        // server rejects (errors 153/145).
        config.websiteDataStore = .default()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Injected into every frame on load — only resets scrollbars/margins so the
        // player surface sits flush. It deliberately does NOT touch any YouTube player
        // UI, overlays, end screens, or branding (.ytp-* etc.) — per YouTube's API ToS,
        // the player is rendered exactly as YouTube serves it.
        let hideScrollbarsCSS = """
        ::-webkit-scrollbar { display: none !important; }
        html, body { overflow: hidden !important; margin: 0 !important; background: #000 !important; }
        .ytp-subtitles-button { display: none !important; }
        """

        let script = WKUserScript(
            source: """
            var style = document.createElement('style');
            style.textContent = `\(hideScrollbarsCSS)`;
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
                const hostName = window.location.hostname.toLowerCase();
                const isYouTube = ['youtube.com', 'youtube-nocookie.com', 'youtu.be'].some(host => hostName === host || hostName.endsWith('.' + host));
                window.nativeVideoZoom = 1;
                window.setNativeVideoZoom = value => {
                    if (isYouTube) { return; }
                    window.nativeVideoZoom = Math.min(3, Math.max(1, Number(value) || 1));
                    document.documentElement.style.backgroundColor = '#000';
                    if (document.body) { document.body.style.backgroundColor = '#000'; }
                    document.querySelectorAll('video').forEach(video => {
                        video.style.backgroundColor = '#000';
                        video.style.transformOrigin = 'center center';
                        video.style.transform = 'scale(' + window.nativeVideoZoom + ')';
                    });
                };

                const postProgress = () => {
                    const video = document.querySelector('video');
                    if (!video) { return; }
                    if (['mp4', 'webm'].includes(window.location.pathname.split('.').pop().toLowerCase())) {
                        video.classList.remove('media-document', 'audio');
                    }
                    if (['mp4', 'webm'].includes(window.location.pathname.split('.').pop().toLowerCase()) && !video.nativePlaylistTracking) {
                        video.nativePlaylistTracking = true;
                        video.controls = false;
                        video.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;max-width:none;max-height:none;margin:0;object-fit:contain';
                        video.addEventListener('ended', () => {
                            window.webkit.messageHandlers.playerBridge.postMessage({event: 'mediaEnded', sourceURL: window.location.href});
                        });
                    }
                    const host = window.location.hostname.toLowerCase();
                    window.setNativeVideoZoom(window.nativeVideoZoom);
                    const params = new URLSearchParams(window.location.search);
                    let videoId = '';
                    if (host.includes('youtube.com') || host.includes('youtu.be') || host.includes('youtube-nocookie.com')) {
                        videoId = params.get('v') || window.location.pathname.split('/').filter(Boolean).pop() || '';
                    } else if (host === 'disneyplus.com' || host.endsWith('.disneyplus.com')) {
                        videoId = 'disneyplus:' + (window.location.pathname || '/');
                    } else if (['mp4', 'webm'].includes(window.location.pathname.split('.').pop().toLowerCase())) {
                        videoId = window.location.pathname.split('.').pop().toLowerCase() + ':' + window.location.href;
                    }
                    if (!videoId) { return; }
                    const titleNode = document.querySelector('ytd-watch-metadata h1 yt-formatted-string');
                    const title = (titleNode && titleNode.textContent ? titleNode.textContent : document.title || '').trim();
                    handler.postMessage({ videoId: videoId, currentTime: video.currentTime || 0, title: title });
                    if (videoId.startsWith('mp4:') || videoId.startsWith('webm:')) {
                        window.webkit.messageHandlers.playerBridge.postMessage({event: 'mediaTime', videoId: videoId,
                            currentTime: video.currentTime || 0, duration: Number.isFinite(video.duration) ? video.duration : 0,
                            state: video.ended ? 0 : (video.paused ? 2 : 1), title: title});
                    }
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
                    if (['mp4', 'webm'].includes(window.location.pathname.split('.').pop().toLowerCase())) {
                        new MutationObserver(postProgress).observe(document.documentElement, {childList: true, subtree: true});
                    }
                };

                install();
            })();
            """,
            injectionTime: .atDocumentEnd,
            // Only non-YouTube pages (e.g. Disney+) are loaded directly into the main
            // frame and tracked this way. YouTube playback runs through the bundled
            // IFrame Player API page and reports progress over `playerBridge` instead.
            forMainFrameOnly: true
        )

        config.userContentController.addUserScript(script)
        config.userContentController.addUserScript(progressTrackingScript)
        config.userContentController.add(scriptHandler, name: "videoProgress")
        config.userContentController.add(scriptHandler, name: "playerBridge")

        initialSavedURL = UserDefaults.standard.string(forKey: lastURLKey).flatMap { URL(string: $0) }
        let savedPositions = UserDefaults.standard.dictionary(forKey: lastPlaybackPositionsKey) as? [String: Double] ?? [:]
        _playbackPositions = State(initialValue: savedPositions)
        _currentVideoID = State(initialValue: nil)
        _currentSourceURL = State(initialValue: initialSavedURL?.absoluteString)
        _pendingInitialURL = State(initialValue: initialSavedURL)
        _statusMessageToken = State(initialValue: nil)

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsBackForwardNavigationGestures = true
        scriptHandler.onPageReady = { [weak wv] in
            DispatchQueue.main.async {
                guard let wv else { return }
                let enabled = AppSettings.shared.fillPlayerWindowEnabled
                wv.evaluateJavaScript("window.setNativeFillPlayerWindow && window.setNativeFillPlayerWindow(\(enabled ? "true" : "false"));")
            }
        }
        wv.navigationDelegate = scriptHandler
        wv.uiDelegate = scriptHandler

        _webView = State(initialValue: wv)

        if initialSavedURL != nil {
            _statusMessage = State(initialValue: "")
        }
    }

    // Bars are visible when hovered (or while the scrub slider is active).
    private var barsVisible: Bool { (isHovering || isScrubbing || playerState != 1) && currentVideoID != nil }

    var body: some View {
        ZStack {
            Color.clear
                .edgesIgnoringSafeArea(.all)

            WebView(
                webView: webView,
                onDrop: { droppedURL in
                    loadStreamingURL(droppedURL)
                },
                onTargetedChange: { isTargeted in
                    DispatchQueue.main.async {
                        if isDropTargeted != isTargeted {
                            isDropTargeted = isTargeted
                        }
                    }
                }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(contentOpacity)
                .onDrop(of: ["public.file-url", "public.url", "public.utf8-plain-text"], isTargeted: $isDropTargeted) { providers in
                    WebView.receiveDrop(providers) { loadStreamingURL($0) }
                }

            if statusMessage != "" {
                VStack {
                    Spacer()
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
                        .padding(.bottom, 22)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.18)))
            }

            Color.clear.overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.red.opacity(0.9), Color.red.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )

                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.18))
                                .frame(width: 76, height: 76)
                            Image(systemName: "play.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Text("Drop Video or URL to Play")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)

                        Text("YouTube · Disney+ · MP4 · WebM")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(36)
                }
                .padding(28)
                .allowsHitTesting(false)
                .opacity(isDropTargeted ? 1 : 0)
            }
            .allowsHitTesting(false)

            // Hover-only overlay bars — top title strip + bottom controls.
            // Visible only while the mouse is over the window (or scrubbing).
            VStack {
                Spacer()
                playerControlBar
            }
            .opacity(barsVisible && !isTransparent ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: barsVisible)
            .allowsHitTesting(barsVisible && !isTransparent)
        }
        .onHover { hovering in
            isHovering = hovering
            handleHoverChange(hovering)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openURL)) { _ in
            promptForURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPlaylist)) { _ in
            showingPlaylist = true
        }
        .sheet(isPresented: $showingPlaylist) {
            PlaylistView(urls: $playlistURLs, currentIndex: playlistIndex) { index in
                playPlaylistItem(index)
            }
        }
        .onChange(of: playlistURLs) { _ in
            if playlistIndex != nil {
                playlistIndex = playlistURLs.firstIndex {
                    StreamingProviderRegistry.shared.resolve($0)?.mediaID == currentVideoID
                }
            }
            UserDefaults.standard.set(playlistURLs, forKey: "playlistURLs")
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
            let sourceURL = notification.userInfo?["sourceURL"] as? String
            settings.pendingPlaybackRequest = nil
            playRecentVideo(videoID: videoID, startTime: time, sourceURL: sourceURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            flushPlaybackPositionToDefaults()
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
            flushPlaybackPositionToDefaults()
            persistLastOpenedVideoFallback()
            pauseAndPersistCurrentPlayback()
            window = nil
        }
        .onAppear(perform: configurePlayback)
        .onDisappear {
            persistLastOpenedVideoFallback()
            hoverMonitorTimer?.invalidate()
            hoverMonitorTimer = nil
        }

    }

    private func configurePlayback() {
        // Progress callback for non-YouTube (Disney+) pages.
        scriptHandler.onProgress = { videoId, time, title in
            updatePlaybackPosition(videoID: videoId, time: time, title: title)
        }
        // IFrame Player API bridge callbacks.
        scriptHandler.onPlayerReady = { handlePlayerReady() }
        scriptHandler.onPlayerStateChange = { state, time, duration in
            DispatchQueue.main.async {
                playerState = state
                if duration > 0 { playerDuration = duration }
                if !isScrubbing { playerCurrentTime = time }
                if state == 0, !(currentVideoID?.hasPrefix("youtube-playlist:") ?? false) {
                    advancePlaylist()
                }
            }
        }
        scriptHandler.onMediaEnded = { sourceURL in
            DispatchQueue.main.async {
                if sourceURL == nil || sourceURL == currentSourceURL { advancePlaylist() }
            }
        }
        scriptHandler.onPlaylistPosition = { id, index in
            DispatchQueue.main.async {
                guard currentVideoID == "youtube-playlist:" + id,
                      var components = URLComponents(string: currentSourceURL ?? "") else { return }
                var items = components.queryItems ?? []
                items.removeAll { $0.name == "index" }
                items.append(URLQueryItem(name: "index", value: String(index + 1)))
                components.queryItems = items
                currentSourceURL = components.url?.absoluteString
            }
        }
        scriptHandler.onPlayerError = { message in
            DispatchQueue.main.async { setStatusMessage(message, clearAfter: 6) }
        }
        scriptHandler.onPlayerTick = { videoId, time, duration, title, state in
            DispatchQueue.main.async {
                playerState = state
                if duration > 0 { playerDuration = duration }
                if !isScrubbing { playerCurrentTime = time }
                if !title.isEmpty { currentVideoTitle = title }
                if !videoId.isEmpty, duration > 0, (state == 1 || state == 2), time > 0 {
                    updatePlaybackPosition(videoID: videoId, time: time, title: title.isEmpty ? nil : title)
                }
            }
        }

        scheduleWindowSetup()
        // Sync initial state with settings
        isAlwaysOnTop = settings.alwaysOnTopEnabled
        setAlwaysOnTop(to: settings.alwaysOnTopEnabled)
        setEightyTransparency(to: settings.eightyTransparencyEnabled)
        setHoverTransparency(to: settings.hoverTransparencyEnabled)
        setFillPlayerWindow(to: settings.fillPlayerWindowEnabled)
        setLockAspectRatio16x9(to: settings.lockAspectRatio16x9Enabled)
        if let request = settings.consumePendingPlaybackRequest() {
            playRecentVideo(videoID: request.videoID, startTime: request.time, sourceURL: request.sourceURL)
        } else if let url = pendingInitialURL {
            pendingInitialURL = nil
            loadStreamingURL(url.absoluteString, rememberAsLast: false)
        } else {
            // Nothing to restore: pre-load the IFrame player shell (no video) so
            // it's ready the moment the user drops a URL.
            loadPlayerPage()
        }
    }

    private var playerTopBar: some View {
        HStack {
            Spacer(minLength: 0)
            Text(currentVideoTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var playerControlBar: some View {
        PlayerToolbar(
            isPlaying: playerState == 1,
            currentTime: $playerCurrentTime,
            duration: playerDuration,
            volume: Binding(get: { playerVolume / 100 }, set: { playerSetVolume($0 * 100) }),
            isScrubbing: $isScrubbing,
            onToggle: playerTogglePlayPause,
            onSeek: { playerSeek(to: playerCurrentTime) },
            onPrevious: previousPlaylistAction,
            onNext: nextPlaylistAction,
            onPlaylist: { showingPlaylist = true },
            videoZoom: isYouTubeActive ? nil : Binding(get: { videoZoom }, set: {
                videoZoom = $0
                evaluatePlayer("window.setNativeVideoZoom && window.setNativeVideoZoom(\($0));")
            })
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var previousPlaylistAction: (() -> Void)? {
        if currentVideoID?.hasPrefix("youtube-playlist:") == true {
            return { evaluatePlayer("window.ytPrevious();") }
        }
        guard let index = playlistIndex, index > 0 else { return nil }
        return { playPlaylistItem(index - 1) }
    }

    private var nextPlaylistAction: (() -> Void)? {
        if currentVideoID?.hasPrefix("youtube-playlist:") == true {
            return { evaluatePlayer("window.ytNext();") }
        }
        guard let index = playlistIndex, playlistURLs.indices.contains(index + 1) else { return nil }
        return { playPlaylistItem(index + 1) }
    }

    func loadStreamingURL(_ urlString: String, rememberAsLast: Bool = true) {
        playlistIndex = nil
        let initialMedia = StreamingProviderRegistry.shared.resolve(urlString)
        if let mediaID = initialMedia?.mediaID {
            let savedTime = playbackPositions[mediaID]
            let startTime = (savedTime ?? 0) >= 1 ? Int(savedTime ?? 0) : nil
            let media = StreamingProviderRegistry.shared.resolve(urlString, startTime: startTime) ?? initialMedia
            if let media {
                loadMedia(media, startTime: startTime.map(Double.init) ?? 0, rememberAsLast: rememberAsLast)
            }
        } else {
            DispatchQueue.main.async {
                statusMessage = "Invalid streaming URL"
            }
        }
    }

    func loadYouTubeURL(_ urlString: String, rememberAsLast: Bool = true) {
        loadStreamingURL(urlString, rememberAsLast: rememberAsLast)
    }

    func promptForURL() {
        let alert = NSAlert()
        alert.messageText = "Open Streaming URL"
        alert.informativeText = "Enter a YouTube, Disney+, MP4, or WebM URL. You can also drop a video file onto the player."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "https://youtube.com/watch?v=... or https://www.disneyplus.com/..."
        alert.accessoryView = textField

        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let urlString = textField.stringValue
            loadStreamingURL(urlString)
        }
    }

    func playRecentVideo(videoID: String, startTime: Double, sourceURL: String? = nil) {
        if let sourceURL,
           StreamingProviderRegistry.shared.resolves(sourceURL, to: videoID),
           let media = StreamingProviderRegistry.shared.resolve(sourceURL, startTime: Int(startTime.rounded())) {
            loadMedia(media, startTime: startTime, rememberAsLast: true)
            return
        }
        loadVideo(videoID: videoID, startTime: startTime, rememberAsLast: true)
    }

    func loadVideo(videoID: String, startTime: Double, rememberAsLast: Bool) {
        guard let url = StreamingProviderRegistry.shared.playbackURL(for: videoID, startTime: adjustedResumeStartTime(from: startTime)) else { return }
        guard let media = StreamingProviderRegistry.shared.resolve(url.absoluteString) else { return }
        loadMedia(media, startTime: startTime, rememberAsLast: rememberAsLast)
    }

    private func playPlaylistItem(_ index: Int) {
        guard playlistURLs.indices.contains(index),
              let media = StreamingProviderRegistry.shared.resolve(playlistURLs[index]) else { return }
        playlistIndex = index
        showingPlaylist = false
        currentVideoID = nil
        loadMedia(media, startTime: 0, rememberAsLast: true)
    }

    private func advancePlaylist() {
        guard let index = playlistIndex else { return }
        if playlistURLs.indices.contains(index + 1) {
            playPlaylistItem(index + 1)
        } else {
            playlistIndex = nil
        }
    }

    func loadMedia(_ media: StreamingMedia, startTime: Double, rememberAsLast: Bool) {
        if media.playbackURL.isFileURL,
           !FileManager.default.isReadableFile(atPath: media.playbackURL.path) {
            setStatusMessage("This video file is unavailable or cannot be read.")
            return
        }
        if rememberAsLast {
            settings.allowRecording(videoID: media.mediaID)
        }
        DispatchQueue.main.async {
            // For YouTube, use the canonical watch URL as the source reference so
            // URL-based history and ID extraction continue to work correctly.
            let sourceURL: String
            if media.providerID == "youtube", !media.mediaID.hasPrefix("youtube-playlist:") {
                sourceURL = "https://www.youtube.com/watch?v=\(media.mediaID)"
            } else {
                sourceURL = media.playbackURL.absoluteString
            }

            if currentVideoID == media.mediaID, currentSourceURL == sourceURL, playerState != 0 {
                currentVideoID = media.mediaID
                currentSourceURL = sourceURL
                applyHistoryNotice(historyEntry(for: media.mediaID))
                if rememberAsLast {
                    UserDefaults.standard.set(sourceURL, forKey: lastURLKey)
                }
                return
            }
            let historyEntry = historyEntry(for: media.mediaID)
            currentVideoID = media.mediaID
            currentSourceURL = sourceURL
            currentVideoTitle = media.defaultTitle
            playerCurrentTime = 0
            playerDuration = 0
            playerState = -1
            videoZoom = 1

            if media.providerID == "youtube" {
                // Render through YouTube's official IFrame Player API (player.html),
                // never by loading the youtube.com/watch page directly.
                statusMessage = ""
                let index = URLComponents(url: media.playbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "index" })?.value.flatMap(Int.init) ?? 1
                loadYouTube(id: media.mediaID, start: Double(adjustedResumeStartTime(from: startTime)), autoplay: true, playlistIndex: max(0, index - 1))
            } else {
                // Non-YouTube providers (e.g. Disney+) load their page directly.
                isYouTubeActive = false
                playerPageLoaded = false
                playerReady = false
                statusMessage = ""
                if media.playbackURL.isFileURL {
                    webView.loadFileURL(media.playbackURL, allowingReadAccessTo: media.playbackURL)
                } else {
                    webView.load(URLRequest(url: media.playbackURL))
                }
            }

            applyHistoryNotice(historyEntry)
            if rememberAsLast {
                UserDefaults.standard.set(sourceURL, forKey: lastURLKey)
            }
        }
    }

    // MARK: - IFrame Player API

    /// Loads player.html with baseURL https://www.youtube.com so YouTube's
    /// embed server accepts the origin and the IFrame API postMessage channel works.
    private func loadPlayerPage() {
        guard let url = Bundle.main.url(forResource: "player", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            statusMessage = "Player page missing"
            return
        }
        playerReady = false
        playerPageLoaded = true
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))
    }

    private func ensurePlayerPage() {
        if !playerPageLoaded {
            loadPlayerPage()
        }
    }

    /// Routes a YouTube video to the IFrame player, queuing it if the player
    /// isn't ready yet. Never autoplays until the player page is mounted/ready.
    private func loadYouTube(id: String, start: Double, autoplay: Bool, playlistIndex: Int = 0) {
        isYouTubeActive = true
        ensurePlayerPage()
        if playerReady {
            evaluatePlayer("window.ytLoad(\(jsString(id)), \(Int(start)), \(autoplay), \(playlistIndex));")
        } else {
            pendingYouTubeID = id
            pendingYouTubeStart = start
            pendingYouTubeAutoplay = autoplay
            pendingPlaylistIndex = playlistIndex
        }
    }

    private func handlePlayerReady() {
        playerReady = true
        if let id = pendingYouTubeID {
            pendingYouTubeID = nil
            evaluatePlayer("window.ytLoad(\(jsString(id)), \(Int(pendingYouTubeStart)), \(pendingYouTubeAutoplay), \(pendingPlaylistIndex));")
        }
        if playerVolume != 100 {
            evaluatePlayer("window.ytSetVolume(\(Int(playerVolume)));")
        }
    }

    private func evaluatePlayer(_ script: String) {
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script)
        }
    }

    /// JSON-encodes a string for safe interpolation into evaluated JavaScript.
    private func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast()) // strip surrounding [ ]
    }

    // Native control-bar actions, all routed through documented IFrame API methods.
    private func playerTogglePlayPause() {
        if !isYouTubeActive {
            evaluatePlayer("var v=document.querySelector('video'); if(v) { v.paused ? v.play() : v.pause(); window.nativePostPlaybackProgress && window.nativePostPlaybackProgress(); }")
            return
        }
        if playerState == 1 { // playing
            evaluatePlayer("window.ytPause();")
        } else {
            evaluatePlayer("window.ytPlay();")
        }
    }

    private func playerSeek(to seconds: Double) {
        guard seconds.isFinite else { return }
        if !isYouTubeActive {
            evaluatePlayer("var v=document.querySelector('video'); if(v) v.currentTime=\(seconds);")
            return
        }
        evaluatePlayer("window.ytSeek(\(seconds));")
    }

    private func playerSetVolume(_ value: Double) {
        playerVolume = value
        if !isYouTubeActive {
            evaluatePlayer("var v=document.querySelector('video'); if(v) v.volume=\(min(1, max(0, value / 100)));")
            return
        }
        evaluatePlayer("window.ytSetVolume(\(Int(value)));")
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

    private func setStatusMessage(_ message: String, clearAfter: TimeInterval = 2) {
        let token = UUID()
        statusMessageToken = token
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) {
            if self.statusMessageToken == token {
                self.statusMessage = ""
            }
        }
    }

    private func showTemporaryHistoryNotice(_ message: String, duration: TimeInterval) {
        historyNoticeClearTask?.cancel()
        let token = UUID()
        statusMessageToken = token
        statusMessage = message
        let clearTask = DispatchWorkItem {
            if self.statusMessageToken == token {
                self.statusMessage = ""
            }
            self.historyNoticeClearTask = nil
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

        // Default to a small 16:9 window if no saved frame exists
        if UserDefaults.standard.string(forKey: playerWindowFrameKey) == nil,
           let screen = window.screen ?? NSScreen.main {
            let w: CGFloat = 1024
            let h: CGFloat = 576
            let x = screen.visibleFrame.midX - w / 2
            let y = screen.visibleFrame.midY - h / 2
            window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
        }

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
            if hovering && NSEvent.pressedMouseButtons == 0 && !isDropTargeted {
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
        let hoveringNow = contentRectInScreen.contains(mouseLocation) && NSEvent.pressedMouseButtons == 0 && !isDropTargeted
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
                // Reset to opaque until hover
                contentOpacity = 1.0
                window.ignoresMouseEvents = false
                ensureWindowFront(window)
                setStatusMessage("Hover mode enabled")
            } else {
                // Always opaque and clickable
                contentOpacity = 1.0
                window.ignoresMouseEvents = false
                ensureWindowFront(window)
                setStatusMessage("Hover mode disabled")
            }
        }
    }

    func setAlwaysOnTop(to enabled: Bool) {
        isAlwaysOnTop = enabled
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
            applyAlwaysOnTopState(window)
            if enabled { ensureWindowFront(window) }
            setStatusMessage(enabled ? "Always on top enabled" : "Always on top disabled")
        }
    }

    func toggleOpacity() {
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
            isDimmed.toggle()
            isEightyTransparency = false
            isTransparent = false
            settings.eightyTransparencyEnabled = false
            settings.hoverTransparencyEnabled = false

            // Dim to 25% or restore to fully opaque; keep clicks enabled
            let newOpacity: Double = isDimmed ? 0.25 : 1.0
            contentOpacity = newOpacity
            window.ignoresMouseEvents = false
            applyTransparentWindowAppearance(window, isFullyTransparent: newOpacity == 0)
            applyTransparentSurfaceMode()

            setStatusMessage(isDimmed ? "Opacity 25%" : "Opacity 100%")
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

            setStatusMessage(enabled ? "Transparency 80% enabled" : "Transparency reset")
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
                setStatusMessage("Hover mode enabled")
            } else {
                stopHoverMonitor()
                isHovering = false
                contentOpacity = 1.0
                window.ignoresMouseEvents = false
                applyTransparentWindowAppearance(window, isFullyTransparent: false)
                setStatusMessage("Hover mode disabled")
            }
            applyTransparentSurfaceMode()
            ensureWindowFront(window)
        }
    }

    func setFillPlayerWindow(to enabled: Bool) {
        isFillPlayerWindowEnabled = enabled
        DispatchQueue.main.async {
            let script = "window.setNativeFillPlayerWindow && window.setNativeFillPlayerWindow(\(enabled ? "true" : "false"));"
            webView.evaluateJavaScript(script)
            setStatusMessage(enabled ? "Fill player window enabled" : "Fill player window disabled")
        }
    }

    func setLockAspectRatio16x9(to enabled: Bool) {
        DispatchQueue.main.async {
            guard let window = getWindow() else { return }
            windowCoordinator.lockAspectRatio16x9 = enabled
            if enabled {
                windowCoordinator.applyLockedAspectRatio(to: window)
            }
            setStatusMessage(enabled ? "16:9 resize lock enabled" : "16:9 resize lock disabled")
        }
    }

    private func ensureWindowFront(_ window: NSWindow) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        applyAlwaysOnTopState(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func updatePlaybackPosition(videoID: String, time: Double, title: String?) {
        DispatchQueue.main.async {
            guard time.isFinite, time >= 0 else { return }
            if playlistIndex != nil, currentVideoID != videoID { return }
            currentVideoID = videoID
            if let pageURL = webView.url?.absoluteString,
               StreamingProviderRegistry.shared.resolves(pageURL, to: videoID) {
                currentSourceURL = pageURL
            }
            playbackPositions[videoID] = time
            UserDefaults.standard.set(playbackPositions, forKey: lastPlaybackPositionsKey)
            let lastWatchURL = currentSourceURL ?? URLHelper.makeWatchURL(videoID: videoID, startTime: Optional<Int>.none)
            UserDefaults.standard.set(lastWatchURL, forKey: lastURLKey)
            AppSettings.shared.recordRecentVideo(videoID: videoID, title: title, position: time, sourceURL: lastWatchURL)
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
        let watchURL = currentSourceURL ?? URLHelper.makeWatchURL(videoID: videoID, startTime: savedTime)
        UserDefaults.standard.set(watchURL, forKey: lastURLKey)
    }

    // Synchronous Swift-side flush — called before any async JS on close/quit so the
    // last known position is guaranteed on disk even if the WKWebView tears down first.
    private func flushPlaybackPositionToDefaults() {
        UserDefaults.standard.set(playbackPositions, forKey: lastPlaybackPositionsKey)
        if let videoID = activeVideoID() {
            let savedTime = playbackPositions[videoID].flatMap { $0 >= 1 ? Int($0.rounded()) : nil }
            let url = currentSourceURL ?? URLHelper.makeWatchURL(videoID: videoID, startTime: savedTime)
            UserDefaults.standard.set(url, forKey: lastURLKey)
        }
        UserDefaults.standard.synchronize()
    }

    private func pauseAndPersistCurrentPlayback() {
        // For YouTube, pause through the IFrame API; for non-YouTube pages, pause the
        // page's own <video> element (and flush its last reported position).
        let script = """
        (function() {
            if (window.ytPause) { window.ytPause(); }
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
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbarStyle = .unifiedCompact
            window.styleMask.insert(.fullSizeContentView)
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
        // Prefer the SwiftUI-assigned main-player window identifier before falling back to heuristics
        if window.identifier == NSUserInterfaceItemIdentifier("main-player") { return true }
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

final class YouTubeScriptMessageHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var onProgress: ((String, Double, String?) -> Void)?
    var onPageReady: (() -> Void)?

    // IFrame Player API bridge callbacks
    var onPlayerReady: (() -> Void)?
    var onPlayerStateChange: ((_ state: Int, _ time: Double, _ duration: Double) -> Void)?
    var onPlayerTick: ((_ videoId: String, _ time: Double, _ duration: Double, _ title: String, _ state: Int) -> Void)?
    var onPlayerError: ((_ message: String) -> Void)?
    var onMediaEnded: ((String?) -> Void)?
    var onPlaylistPosition: ((String, Int) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "videoProgress":
            guard let body = message.body as? [String: Any],
                  let videoId = body["videoId"] as? String,
                  let currentTime = body["currentTime"] as? Double else { return }
            onProgress?(videoId, currentTime, body["title"] as? String)
        case "playerBridge":
            handlePlayerBridge(message.body)
        default:
            break
        }
    }

    private func handlePlayerBridge(_ rawBody: Any) {
        guard let body = rawBody as? [String: Any],
              let event = body["event"] as? String else { return }
        switch event {
        case "ready":
            onPlayerReady?()
        case "state":
            let state = body["state"] as? Int ?? -1
            let time = body["currentTime"] as? Double ?? 0
            let duration = body["duration"] as? Double ?? 0
            onPlayerStateChange?(state, time, duration)
        case "time", "mediaTime":
            let playlistID = body["playlistId"] as? String ?? ""
            let videoId = playlistID.isEmpty ? (body["videoId"] as? String ?? "") : "youtube-playlist:" + playlistID
            if !playlistID.isEmpty, let index = body["playlistIndex"] as? Int, index >= 0 {
                onPlaylistPosition?(playlistID, index)
            }
            let time = body["currentTime"] as? Double ?? 0
            let duration = body["duration"] as? Double ?? 0
            let title = body["title"] as? String ?? ""
            let state = body["state"] as? Int ?? -1
            onPlayerTick?(videoId, time, duration, title, state)
        case "playlistEnded":
            onMediaEnded?(nil)
        case "mediaEnded":
            if let sourceURL = body["sourceURL"] as? String { onMediaEnded?(sourceURL) }
        case "error":
            let code = body["code"] as? Int ?? -1
            let message: String
            switch code {
            case 2:   message = "Invalid video ID"
            case 5:   message = "Playback error (HTML5)"
            case 100: message = "Video not found"
            case 101, 150: message = "This video can't be embedded"
            case 152: message = "Embed origin rejected"
            case 153, 145: message = "Origin error — check embed setup"
            default:  message = "Player error \(code)"
            }
            onPlayerError?(message)
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onPageReady?()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

final class PlayerWindowCoordinator: NSObject, NSWindowDelegate {
    var lockAspectRatio16x9 = false
    var onFrameChanged: ((NSRect) -> Void)?
    private var isAdjustingFrame = false

    // Corrects the proposed size before it's committed/painted, so interactive
    // resizing (drag handles, or any resize that goes through AppKit's normal
    // negotiation) never draws a wrong-aspect frame in the first place — this
    // is what avoids the flicker a reactive (windowDidResize) fix causes.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard lockAspectRatio16x9 else { return frameSize }
        let contentSize = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        guard contentSize.width > 0 else { return frameSize }
        let targetContentSize = NSSize(width: contentSize.width, height: round(contentSize.width * 9.0 / 16.0))
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
    }

    // Backstop for resizes that bypass windowWillResize entirely (e.g. an
    // external window manager setting the frame directly). No-op when
    // windowWillResize already applied the correct size.
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

        // Applied synchronously (not deferred to the next run loop turn) so the
        // correction lands before an external window manager (e.g. AeroSpace)
        // re-asserts its own tile geometry in response to this same resize.
        isAdjustingFrame = true
        window.setFrame(adjustedFrame, display: true)
        isAdjustingFrame = false
    }
}

/// Serves player.html from a custom `clipframe://` scheme so the page has a
/// recognisable HTTPS-equivalent origin that YouTube's embed server accepts.
/// Using file:// gives a null origin (error 153) and using youtube.com triggers
/// the self-embedding block (error 152). A custom scheme avoids both.
final class PlayerPageSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.host == "localhost",
              url.path == "/player.html",
              let fileURL = Bundle.main.url(forResource: "player", withExtension: "html"),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
