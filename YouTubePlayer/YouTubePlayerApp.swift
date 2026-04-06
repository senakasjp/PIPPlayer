import SwiftUI
import Combine

struct RecentVideoItem: Codable, Identifiable, Hashable {
    let videoID: String
    var title: String
    var lastPosition: Double
    var lastPlayedAt: Date
    var watchLaterStars: Int
    var isThumbsDown: Bool
    var watchNote: String

    var id: String { videoID }

    init(videoID: String, title: String, lastPosition: Double, lastPlayedAt: Date, watchLaterStars: Int = 0, isThumbsDown: Bool = false, watchNote: String = "") {
        self.videoID = videoID
        self.title = title
        self.lastPosition = lastPosition
        self.lastPlayedAt = lastPlayedAt
        self.watchLaterStars = min(5, max(0, watchLaterStars))
        self.isThumbsDown = isThumbsDown
        self.watchNote = watchNote
    }

    private enum CodingKeys: String, CodingKey {
        case videoID, title, lastPosition, lastPlayedAt, watchLaterStars, isThumbsDown, watchNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoID = try container.decode(String.self, forKey: .videoID)
        title = try container.decode(String.self, forKey: .title)
        lastPosition = try container.decode(Double.self, forKey: .lastPosition)
        lastPlayedAt = try container.decode(Date.self, forKey: .lastPlayedAt)
        watchLaterStars = min(5, max(0, try container.decodeIfPresent(Int.self, forKey: .watchLaterStars) ?? 0))
        isThumbsDown = try container.decodeIfPresent(Bool.self, forKey: .isThumbsDown) ?? false
        watchNote = try container.decodeIfPresent(String.self, forKey: .watchNote) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(videoID, forKey: .videoID)
        try container.encode(title, forKey: .title)
        try container.encode(lastPosition, forKey: .lastPosition)
        try container.encode(lastPlayedAt, forKey: .lastPlayedAt)
        try container.encode(min(5, max(0, watchLaterStars)), forKey: .watchLaterStars)
        try container.encode(isThumbsDown, forKey: .isThumbsDown)
        try container.encode(watchNote, forKey: .watchNote)
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard
    let maxRecentVideos = 20
    let maxWatchHistoryVideos = 500

    private enum Keys {
        static let alwaysOnTop = "settings.alwaysOnTopEnabled"
        static let eightyTransparency = "settings.eightyTransparencyEnabled"
        static let hoverTransparency = "settings.hoverTransparencyEnabled"
        static let fillPlayerWindow = "settings.fillPlayerWindowEnabled"
        static let lockAspectRatio16x9 = "settings.lockAspectRatio16x9Enabled"
        static let recentVideos = "settings.recentVideos"
        static let watchHistoryVideos = "settings.watchHistoryVideos"
    }

    @Published var recentVideos: [RecentVideoItem] = [] {
        didSet {
            guard oldValue != recentVideos else { return }
            persistRecentVideos()
            NotificationCenter.default.post(name: .recentVideosUpdated, object: nil)
        }
    }

    @Published var watchHistoryVideos: [RecentVideoItem] = [] {
        didSet {
            guard oldValue != watchHistoryVideos else { return }
            persistWatchHistoryVideos()
            NotificationCenter.default.post(name: .watchHistoryUpdated, object: nil)
        }
    }

    @Published var alwaysOnTopEnabled: Bool = true {
        didSet {
            guard oldValue != alwaysOnTopEnabled else { return }
            defaults.set(alwaysOnTopEnabled, forKey: Keys.alwaysOnTop)
            NotificationCenter.default.post(name: .setAlwaysOnTop, object: nil, userInfo: ["enabled": alwaysOnTopEnabled])
        }
    }

    @Published var eightyTransparencyEnabled: Bool = false {
        didSet {
            guard oldValue != eightyTransparencyEnabled else { return }
            defaults.set(eightyTransparencyEnabled, forKey: Keys.eightyTransparency)
            NotificationCenter.default.post(name: .setEightyTransparency, object: nil, userInfo: ["enabled": eightyTransparencyEnabled])
        }
    }

    @Published var hoverTransparencyEnabled: Bool = true {
        didSet {
            guard oldValue != hoverTransparencyEnabled else { return }
            defaults.set(hoverTransparencyEnabled, forKey: Keys.hoverTransparency)
            NotificationCenter.default.post(name: .setHoverTransparency, object: nil, userInfo: ["enabled": hoverTransparencyEnabled])
        }
    }

    @Published var fillPlayerWindowEnabled: Bool = false {
        didSet {
            guard oldValue != fillPlayerWindowEnabled else { return }
            defaults.set(fillPlayerWindowEnabled, forKey: Keys.fillPlayerWindow)
            NotificationCenter.default.post(name: .setFillPlayerWindow, object: nil, userInfo: ["enabled": fillPlayerWindowEnabled])
        }
    }

    @Published var lockAspectRatio16x9Enabled: Bool = false {
        didSet {
            guard oldValue != lockAspectRatio16x9Enabled else { return }
            defaults.set(lockAspectRatio16x9Enabled, forKey: Keys.lockAspectRatio16x9)
            NotificationCenter.default.post(name: .setLockAspectRatio16x9, object: nil, userInfo: ["enabled": lockAspectRatio16x9Enabled])
        }
    }

    private init() {
        loadPersistedValues()
    }

    private func loadPersistedValues() {
        if defaults.object(forKey: Keys.alwaysOnTop) != nil {
            alwaysOnTopEnabled = defaults.bool(forKey: Keys.alwaysOnTop)
        }
        if defaults.object(forKey: Keys.eightyTransparency) != nil {
            eightyTransparencyEnabled = defaults.bool(forKey: Keys.eightyTransparency)
        }
        if defaults.object(forKey: Keys.hoverTransparency) != nil {
            hoverTransparencyEnabled = defaults.bool(forKey: Keys.hoverTransparency)
        }
        if defaults.object(forKey: Keys.fillPlayerWindow) != nil {
            fillPlayerWindowEnabled = defaults.bool(forKey: Keys.fillPlayerWindow)
        }
        if defaults.object(forKey: Keys.lockAspectRatio16x9) != nil {
            lockAspectRatio16x9Enabled = defaults.bool(forKey: Keys.lockAspectRatio16x9)
        }
        if let data = defaults.data(forKey: Keys.recentVideos),
           let decoded = try? JSONDecoder().decode([RecentVideoItem].self, from: data) {
            recentVideos = normalizedVideos(decoded, maxCount: maxRecentVideos)
        }
        if let data = defaults.data(forKey: Keys.watchHistoryVideos),
           let decoded = try? JSONDecoder().decode([RecentVideoItem].self, from: data) {
            watchHistoryVideos = normalizedVideos(decoded, maxCount: maxWatchHistoryVideos)
        }
    }

    func recordRecentVideo(videoID: String, title: String?, position: Double) {
        let cleanedTitle = cleanedVideoTitle(title)
            ?? recentVideos.first(where: { $0.videoID == videoID })?.title
            ?? watchHistoryVideos.first(where: { $0.videoID == videoID })?.title
            ?? "YouTube Video"
        let safePosition = max(0, position)
        let now = Date()

        recentVideos = upsertVideo(
            in: recentVideos,
            videoID: videoID,
            title: cleanedTitle,
            position: safePosition,
            playedAt: now,
            maxCount: maxRecentVideos
        )

        watchHistoryVideos = upsertVideo(
            in: watchHistoryVideos,
            videoID: videoID,
            title: cleanedTitle,
            position: safePosition,
            playedAt: now,
            maxCount: maxWatchHistoryVideos
        )
    }

    func removeHistoryVideo(videoID: String) {
        watchHistoryVideos.removeAll { $0.videoID == videoID }
    }

    func removeRecentVideo(videoID: String) {
        recentVideos.removeAll { $0.videoID == videoID }
    }

    func clearRecentVideos() {
        recentVideos = []
    }

    func clearWatchHistoryVideos() {
        watchHistoryVideos = []
    }

    func setWatchLaterStars(videoID: String, stars: Int) {
        let clamped = min(5, max(1, stars))
        if let index = watchHistoryVideos.firstIndex(where: { $0.videoID == videoID }) {
            watchHistoryVideos[index].watchLaterStars = clamped
            watchHistoryVideos[index].isThumbsDown = false
        }
        if let index = recentVideos.firstIndex(where: { $0.videoID == videoID }) {
            recentVideos[index].watchLaterStars = clamped
            recentVideos[index].isThumbsDown = false
        }
    }

    func setThumbsDown(videoID: String, isThumbsDown: Bool) {
        if let index = watchHistoryVideos.firstIndex(where: { $0.videoID == videoID }) {
            watchHistoryVideos[index].isThumbsDown = isThumbsDown
            if isThumbsDown {
                watchHistoryVideos[index].watchLaterStars = 0
            }
        }
        if let index = recentVideos.firstIndex(where: { $0.videoID == videoID }) {
            recentVideos[index].isThumbsDown = isThumbsDown
            if isThumbsDown {
                recentVideos[index].watchLaterStars = 0
            }
        }
    }

    func setWatchHistoryNote(videoID: String, note: String) {
        if let index = watchHistoryVideos.firstIndex(where: { $0.videoID == videoID }) {
            watchHistoryVideos[index].watchNote = note
        }
        if let index = recentVideos.firstIndex(where: { $0.videoID == videoID }) {
            recentVideos[index].watchNote = note
        }
    }

    private func persistRecentVideos() {
        guard let data = try? JSONEncoder().encode(recentVideos) else { return }
        defaults.set(data, forKey: Keys.recentVideos)
    }

    private func persistWatchHistoryVideos() {
        guard let data = try? JSONEncoder().encode(watchHistoryVideos) else { return }
        defaults.set(data, forKey: Keys.watchHistoryVideos)
    }

    private func upsertVideo(
        in videos: [RecentVideoItem],
        videoID: String,
        title: String,
        position: Double,
        playedAt: Date,
        maxCount: Int
    ) -> [RecentVideoItem] {
        var updated = normalizedVideos(videos, maxCount: maxCount)
        if let index = updated.firstIndex(where: { $0.videoID == videoID }) {
            updated[index].title = title
            updated[index].lastPosition = position
            updated[index].lastPlayedAt = playedAt
        } else {
            updated.append(RecentVideoItem(videoID: videoID, title: title, lastPosition: position, lastPlayedAt: playedAt))
        }
        updated.sort { $0.lastPlayedAt > $1.lastPlayedAt }
        if updated.count > maxCount {
            updated = Array(updated.prefix(maxCount))
        }
        return updated
    }

    private func normalizedVideos(_ videos: [RecentVideoItem], maxCount: Int) -> [RecentVideoItem] {
        let sorted = videos.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        var byID: [String: RecentVideoItem] = [:]

        for video in sorted {
            if var existing = byID[video.videoID] {
                if existing.watchNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !video.watchNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existing.watchNote = video.watchNote
                }
                existing.watchLaterStars = max(existing.watchLaterStars, video.watchLaterStars)
                existing.isThumbsDown = existing.isThumbsDown || video.isThumbsDown
                byID[video.videoID] = existing
            } else {
                byID[video.videoID] = video
            }
        }

        var normalized = Array(byID.values).sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        if normalized.count > maxCount {
            normalized = Array(normalized.prefix(maxCount))
        }
        return normalized
    }

    private func cleanedVideoTitle(_ rawTitle: String?) -> String? {
        guard let rawTitle else { return nil }
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let suffix = " - YouTube"
        if trimmed.hasSuffix(suffix) {
            return String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static func formatPlaybackTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func recentVideoMenuTitle(_ video: RecentVideoItem) -> String {
        video.title
    }
}

struct WatchHistoryView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @State private var expandedNotes: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.watchHistoryVideos.isEmpty {
                Text("No watch history yet")
                    .foregroundColor(.secondary)
                    .padding(16)
                Spacer()
            } else {
                List {
                    ForEach(settings.watchHistoryVideos) { video in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                Button {
                                    openWindow(id: "main-player")
                                    NotificationCenter.default.post(name: .openRecentVideo, object: nil, userInfo: ["videoID": video.videoID, "time": video.lastPosition])
                                } label: {
                                    HStack(spacing: 10) {
                                        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(video.videoID)/mqdefault.jpg")) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Rectangle().fill(Color.gray.opacity(0.25))
                                        }
                                        .frame(width: 72, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(video.title)
                                                .lineLimit(2)
                                            Text("Resume at \(AppSettings.formatPlaybackTime(video.lastPosition))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    settings.setThumbsDown(videoID: video.videoID, isThumbsDown: !video.isThumbsDown)
                                } label: {
                                    Image(systemName: video.isThumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                        .foregroundColor(video.isThumbsDown ? .red : .secondary)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(video.isThumbsDown ? "Remove thumbs down" : "Mark as thumbs down")

                                Button {
                                    toggleNotes(for: video.videoID)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(expandedNotes.contains(video.videoID) ? "Collapse" : "Notes")
                                        if hasNotes(videoID: video.videoID) {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                StarRatingView(rating: video.watchLaterStars) { rating in
                                    settings.setWatchLaterStars(videoID: video.videoID, stars: rating)
                                }

                                Button(role: .destructive) {
                                    removeHistoryVideo(videoID: video.videoID)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Remove from watch history")
                            }

                            if expandedNotes.contains(video.videoID) {
                                TextEditor(text: noteBinding(for: video.videoID))
                                    .frame(minHeight: 70, maxHeight: 110)
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private func toggleNotes(for videoID: String) {
        if expandedNotes.contains(videoID) {
            expandedNotes.remove(videoID)
        } else {
            expandedNotes.insert(videoID)
        }
    }

    private func removeHistoryVideo(videoID: String) {
        expandedNotes.remove(videoID)
        settings.removeHistoryVideo(videoID: videoID)
    }

    private func noteBinding(for videoID: String) -> Binding<String> {
        Binding(
            get: {
                settings.watchHistoryVideos.first(where: { $0.videoID == videoID })?.watchNote ?? ""
            },
            set: { newValue in
                settings.setWatchHistoryNote(videoID: videoID, note: newValue)
            }
        )
    }

    private func hasNotes(videoID: String) -> Bool {
        let note = settings.watchHistoryVideos.first(where: { $0.videoID == videoID })?.watchNote ?? ""
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct StarRatingView: View {
    let rating: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(value <= rating ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Set watch later priority: \(value) star\(value == 1 ? "" : "s")")
            }
        }
    }
}

struct PlayerCommands: Commands {
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .sidebar) {
            Toggle("Hover Transparency", isOn: $settings.hoverTransparencyEnabled)
                .keyboardShortcut("t", modifiers: .command)
            Toggle("Always On Top", isOn: $settings.alwaysOnTopEnabled)
                .keyboardShortcut("l", modifiers: .command)
            Toggle("80% Transparency", isOn: $settings.eightyTransparencyEnabled)
                .keyboardShortcut("8", modifiers: .command)
            Button("Toggle Opacity") {
                NotificationCenter.default.post(name: .toggleOpacity, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)
        }

        CommandMenu("Player") {
            Button("Open URL...") {
                NotificationCenter.default.post(name: .openURL, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Watch History") {
                openWindow(id: "watch-history")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Toggle("Fill Player Window", isOn: $settings.fillPlayerWindowEnabled)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Lock 16:9 While Resizing", isOn: $settings.lockAspectRatio16x9Enabled)
        }
    }
}

@main
struct YouTubePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        Window("YouTube Player", id: "main-player") {
            ContentView()
                .environmentObject(settings)
        }
        .commands {
            PlayerCommands(settings: settings)
        }

        Window("Watch History", id: "watch-history") {
            WatchHistoryView()
                .environmentObject(settings)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private let settings = AppSettings.shared
    private var observers: [NSObjectProtocol] = []
    private var thumbnailCache: [String: NSImage] = [:]
    private var alwaysOnTopItem: NSMenuItem?
    private var eightyTransparencyItem: NSMenuItem?
    private var hoverTransparencyItem: NSMenuItem?
    private var fillPlayerWindowItem: NSMenuItem?
    private var lockAspectRatio16x9Item: NSMenuItem?
    private var recentVideosItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let icon = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "YouTube Player")
            icon?.size = NSSize(width: 14, height: 14)
            button.image = icon
            button.imageScaling = .scaleProportionallyDown
        }

        setupMenu()
        installObservers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Open URL...", action: #selector(openURL), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        let hoverTransparency = NSMenuItem(title: "Hover Transparency", action: #selector(toggleHoverTransparency), keyEquivalent: "t")
        hoverTransparency.state = settings.hoverTransparencyEnabled ? .on : .off
        menu.addItem(hoverTransparency)
        hoverTransparencyItem = hoverTransparency

        let alwaysOnTop = NSMenuItem(title: "Always On Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "l")
        alwaysOnTop.state = settings.alwaysOnTopEnabled ? .on : .off
        menu.addItem(alwaysOnTop)
        alwaysOnTopItem = alwaysOnTop

        let eightyTransparency = NSMenuItem(title: "80% Transparency", action: #selector(toggleEightyTransparency), keyEquivalent: "8")
        eightyTransparency.state = settings.eightyTransparencyEnabled ? .on : .off
        menu.addItem(eightyTransparency)
        eightyTransparencyItem = eightyTransparency

        let fillPlayerWindow = NSMenuItem(title: "Fill Player Window", action: #selector(toggleFillPlayerWindow), keyEquivalent: "f")
        fillPlayerWindow.keyEquivalentModifierMask = [.command, .shift]
        fillPlayerWindow.state = settings.fillPlayerWindowEnabled ? .on : .off
        menu.addItem(fillPlayerWindow)
        fillPlayerWindowItem = fillPlayerWindow

        let lockAspectRatio16x9 = NSMenuItem(title: "Lock 16:9 While Resizing", action: #selector(toggleLockAspectRatio16x9), keyEquivalent: "")
        lockAspectRatio16x9.state = settings.lockAspectRatio16x9Enabled ? .on : .off
        menu.addItem(lockAspectRatio16x9)
        lockAspectRatio16x9Item = lockAspectRatio16x9

        let recentVideos = NSMenuItem(title: "Recent Videos", action: nil, keyEquivalent: "")
        let recentSubmenu = NSMenu(title: "Recent Videos")
        recentSubmenu.showsStateColumn = true
        recentVideos.submenu = recentSubmenu
        menu.addItem(recentVideos)
        recentVideosItem = recentVideos
        rebuildRecentVideosMenu()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func openURL() {
        NotificationCenter.default.post(name: .openURL, object: nil)
    }

    @objc func toggleTransparency() {
        NotificationCenter.default.post(name: .toggleTransparency, object: nil)
    }

    @objc func toggleHoverTransparency(_ sender: NSMenuItem) {
        settings.hoverTransparencyEnabled.toggle()
    }

    @objc func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        settings.alwaysOnTopEnabled.toggle()
    }

    @objc func toggleEightyTransparency(_ sender: NSMenuItem) {
        settings.eightyTransparencyEnabled.toggle()
    }

    @objc func toggleFillPlayerWindow(_ sender: NSMenuItem) {
        settings.fillPlayerWindowEnabled.toggle()
    }

    @objc func toggleLockAspectRatio16x9(_ sender: NSMenuItem) {
        settings.lockAspectRatio16x9Enabled.toggle()
    }

    @objc func openRecentVideoFromMenu(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let videoID = info["videoID"] as? String else { return }
        let time = info["time"] as? Double ?? 0
        NotificationCenter.default.post(name: .openRecentVideo, object: nil, userInfo: ["videoID": videoID, "time": time])
    }

    @objc func removeRecentVideoFromMenu(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let videoID = info["videoID"] as? String else { return }
        settings.removeRecentVideo(videoID: videoID)
    }

    @objc func clearRecentVideosFromMenu(_ sender: NSMenuItem) {
        settings.clearRecentVideos()
    }

    private func rebuildRecentVideosMenu() {
        guard let submenu = recentVideosItem?.submenu else { return }
        submenu.removeAllItems()

        let recent = Array(settings.recentVideos.prefix(settings.maxRecentVideos))
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No Recent Videos", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return
        }

        for video in recent {
            let playItem = NSMenuItem(title: AppSettings.recentVideoMenuTitle(video), action: #selector(openRecentVideoFromMenu(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = ["videoID": video.videoID, "time": video.lastPosition]
            applyThumbnail(to: playItem, videoID: video.videoID)
            submenu.addItem(playItem)
        }

        submenu.addItem(NSMenuItem.separator())
        let clearAllItem = NSMenuItem(title: "Clear Recent Videos", action: #selector(clearRecentVideosFromMenu(_:)), keyEquivalent: "")
        clearAllItem.target = self
        submenu.addItem(clearAllItem)
    }

    private func applyThumbnail(to item: NSMenuItem, videoID: String) {
        if let cached = thumbnailCache[videoID] {
            item.image = cached
            return
        }

        guard let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg") else { return }
        URLSession.shared.dataTask(with: url) { [weak self, weak item] data, _, _ in
            guard let self,
                  let data,
                  let image = NSImage(data: data),
                  let thumbnail = self.resizedThumbnail(image) else { return }
            DispatchQueue.main.async {
                thumbnail.isTemplate = false
                self.thumbnailCache[videoID] = thumbnail
                item?.image = thumbnail
                item?.menu?.update()
            }
        }.resume()
    }

    private func resizedThumbnail(_ image: NSImage) -> NSImage? {
        let targetSize = NSSize(width: 28, height: 20)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .setAlwaysOnTop, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.alwaysOnTopItem?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .setEightyTransparency, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.eightyTransparencyItem?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .setHoverTransparency, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.hoverTransparencyItem?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .setFillPlayerWindow, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.fillPlayerWindowItem?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .setLockAspectRatio16x9, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.lockAspectRatio16x9Item?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .recentVideosUpdated, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildRecentVideosMenu()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension Notification.Name {
    static let openURL = Notification.Name("openURL")
    static let toggleTransparency = Notification.Name("toggleTransparency")
    static let toggleOpacity = Notification.Name("toggleOpacity")
    static let setAlwaysOnTop = Notification.Name("setAlwaysOnTop")
    static let setEightyTransparency = Notification.Name("setEightyTransparency")
    static let setHoverTransparency = Notification.Name("setHoverTransparency")
    static let setFillPlayerWindow = Notification.Name("setFillPlayerWindow")
    static let setLockAspectRatio16x9 = Notification.Name("setLockAspectRatio16x9")
    static let openRecentVideo = Notification.Name("openRecentVideo")
    static let recentVideosUpdated = Notification.Name("recentVideosUpdated")
    static let watchHistoryUpdated = Notification.Name("watchHistoryUpdated")
}
