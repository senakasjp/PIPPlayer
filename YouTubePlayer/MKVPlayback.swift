import AppKit
import Combine
import VLCKit

final class MKVVideoSurface: NSView {
    let videoView = VLCVideoView()
    var zoom = 1.0 { didSet { needsLayout = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        videoView.fillScreen = false
        addSubview(videoView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let factor = min(3, max(1, zoom))
        videoView.frame = bounds.insetBy(dx: -bounds.width * (factor - 1) / 2,
                                        dy: -bounds.height * (factor - 1) / 2)
    }
}

final class MKVPlayback: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    struct Snapshot {
        let sessionID: UUID
        let mediaID: String
        let time: Double
        let duration: Double
        let state: Int
    }

    let updates = PassthroughSubject<Snapshot, Never>()
    private(set) var snapshot: Snapshot?
    private(set) var sessionID = UUID()
    let surface = MKVVideoSurface(frame: .zero)
    private static let library = VLCLibrary(options: ["--no-play-and-pause"])
    private var player = VLCMediaPlayer(library: MKVPlayback.library)
    private var currentMedia: StreamingMedia?
    private var timer: Timer?
    private var mediaID: String?
    private var pendingStart: Double?
    private var finished = false

    override init() {
        super.init()
        player.drawable = surface.videoView
    }

    func play(_ media: StreamingMedia, startTime: Double, volume: Double) {
        stop()
        player = VLCMediaPlayer(library: MKVPlayback.library)
        player.drawable = surface.videoView
        player.delegate = self
        currentMedia = media
        mediaID = media.mediaID
        pendingStart = startTime.isFinite ? max(0, startTime) : 0
        finished = false
        player.media = VLCMedia(url: media.playbackURL)
        setVolume(volume)
        player.play()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    func stop() {
        sessionID = UUID()
        timer?.invalidate()
        timer = nil
        mediaID = nil
        currentMedia = nil
        player.delegate = nil
        player.stop()
        player.media = nil
        snapshot = nil
        pendingStart = nil
    }

    func togglePlayPause() {
        if finished, let media = currentMedia {
            play(media, startTime: 0, volume: Double(player.audio?.volume ?? 100))
            return
        }
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, player.isSeekable else { return }
        let milliseconds = min(Double(Int32.max), max(0, seconds * 1000))
        player.time = VLCTime(int: Int32(milliseconds))
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        player.audio?.volume = Int32(min(100, max(0, value)))
    }

    func mediaPlayerStateChanged(_ notification: Notification) {
        guard let sender = notification.object as? VLCMediaPlayer else { return }
        let state = sender.state
        if Thread.isMainThread {
            guard sender === player else { return }
            poll(state: state)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self, sender === self.player else { return }
                self.poll(state: state)
            }
        }
    }

    private func poll(state reportedState: VLCMediaPlayerState? = nil) {
        guard let mediaID, !finished else { return }
        let state: Int
        switch reportedState ?? player.state {
        case .playing: state = 1
        case .paused: state = 2
        case .ended: state = 0
        case .error: state = -1
        default: state = player.isPlaying ? 1 : 3
        }
        if let start = pendingStart, player.isSeekable, state == 1 {
            pendingStart = nil
            if start > 0 { seek(to: start) }
        }
        let time = max(0, Double(player.time.intValue) / 1000)
        let duration = max(0, Double(player.media?.length.intValue ?? 0) / 1000)
        if state == 0 || state == -1 {
            finished = true
            timer?.invalidate()
            timer = nil
        }
        let value = Snapshot(sessionID: sessionID, mediaID: mediaID, time: time, duration: duration, state: state)
        snapshot = value
        updates.send(value)
    }

    deinit {
        player.delegate = nil
        timer?.invalidate()
        player.stop()
        player.drawable = nil
    }
}
