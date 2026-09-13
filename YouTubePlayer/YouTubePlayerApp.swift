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
    var sourceURL: String?

    var id: String { videoID }

    init(videoID: String, title: String, lastPosition: Double, lastPlayedAt: Date, watchLaterStars: Int = 0, isThumbsDown: Bool = false, watchNote: String = "", sourceURL: String? = nil) {
        self.videoID = videoID
        self.title = title
        self.lastPosition = lastPosition
        self.lastPlayedAt = lastPlayedAt
        self.watchLaterStars = min(5, max(0, watchLaterStars))
        self.isThumbsDown = isThumbsDown
        self.watchNote = watchNote
        self.sourceURL = sourceURL
    }

    private enum CodingKeys: String, CodingKey {
        case videoID, title, lastPosition, lastPlayedAt, watchLaterStars, isThumbsDown, watchNote, sourceURL
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
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
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
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
    }
}

struct PlaybackRequest: Equatable {
    let videoID: String
    let time: Double
    let sourceURL: String?

    var userInfo: [String: Any] {
        var info: [String: Any] = ["videoID": videoID, "time": time]
        if let sourceURL {
            info["sourceURL"] = sourceURL
        }
        return info
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
        static let deletedRecentVideoIDs = "settings.deletedRecentVideoIDs"
        static let deletedWatchHistoryVideoIDs = "settings.deletedWatchHistoryVideoIDs"
    }

    private var deletedRecentVideoIDs: Set<String> = []
    private var deletedWatchHistoryVideoIDs: Set<String> = []

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

    var pendingPlaybackRequest: PlaybackRequest?

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

    @Published var fillPlayerWindowEnabled: Bool = true {
        didSet {
            guard oldValue != fillPlayerWindowEnabled else { return }
            defaults.set(fillPlayerWindowEnabled, forKey: Keys.fillPlayerWindow)
            NotificationCenter.default.post(name: .setFillPlayerWindow, object: nil, userInfo: ["enabled": fillPlayerWindowEnabled])
        }
    }

    @Published var lockAspectRatio16x9Enabled: Bool = true {
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
        // fillPlayerWindow and lockAspectRatio16x9 are permanently locked to true —
        // do not restore stored values (a stale `false` from an old install would
        // otherwise silently re-disable them on every launch).
        if let data = defaults.data(forKey: Keys.recentVideos) {
            do {
                let decoded = try JSONDecoder().decode([RecentVideoItem].self, from: data)
                recentVideos = normalizedVideos(decoded, maxCount: maxRecentVideos)
            } catch {
                print("[AppSettings] Failed to decode recentVideos: \(error.localizedDescription)")
                defaults.removeObject(forKey: Keys.recentVideos)
            }
        }
        if let data = defaults.data(forKey: Keys.watchHistoryVideos) {
            do {
                let decoded = try JSONDecoder().decode([RecentVideoItem].self, from: data)
                watchHistoryVideos = normalizedVideos(decoded, maxCount: maxWatchHistoryVideos)
            } catch {
                print("[AppSettings] Failed to decode watchHistoryVideos: \(error.localizedDescription)")
                defaults.removeObject(forKey: Keys.watchHistoryVideos)
            }
        }
        deletedRecentVideoIDs = Set(defaults.stringArray(forKey: Keys.deletedRecentVideoIDs) ?? [])
        deletedWatchHistoryVideoIDs = Set(defaults.stringArray(forKey: Keys.deletedWatchHistoryVideoIDs) ?? [])
    }

    func recordRecentVideo(videoID: String, title: String?, position: Double, sourceURL: String? = nil) {
        let cleanedTitle = cleanedVideoTitle(title)
            ?? recentVideos.first(where: { $0.videoID == videoID })?.title
            ?? watchHistoryVideos.first(where: { $0.videoID == videoID })?.title
            ?? StreamingProviderRegistry.shared.providerName(for: videoID) + " Video"
        let safePosition = max(0, position)
        let now = Date()

        if !deletedRecentVideoIDs.contains(videoID) {
            recentVideos = upsertVideo(
                in: recentVideos,
                videoID: videoID,
                title: cleanedTitle,
                position: safePosition,
                sourceURL: sourceURL,
                playedAt: now,
                maxCount: maxRecentVideos
            )
        }

        if !deletedWatchHistoryVideoIDs.contains(videoID) {
            watchHistoryVideos = upsertVideo(
                in: watchHistoryVideos,
                videoID: videoID,
                title: cleanedTitle,
                position: safePosition,
                sourceURL: sourceURL,
                playedAt: now,
                maxCount: maxWatchHistoryVideos
            )
        }
    }

    func removeHistoryVideo(videoID: String) {
        deletedWatchHistoryVideoIDs.insert(videoID)
        persistDeletedVideoIDs()
        watchHistoryVideos.removeAll { $0.videoID == videoID }
    }

    func removeRecentVideo(videoID: String) {
        deletedRecentVideoIDs.insert(videoID)
        persistDeletedVideoIDs()
        recentVideos.removeAll { $0.videoID == videoID }
    }

    func clearRecentVideos() {
        deletedRecentVideoIDs.formUnion(recentVideos.map(\.videoID))
        persistDeletedVideoIDs()
        recentVideos = []
    }

    func clearWatchHistoryVideos() {
        deletedWatchHistoryVideoIDs.formUnion(watchHistoryVideos.map(\.videoID))
        persistDeletedVideoIDs()
        watchHistoryVideos = []
    }

    func allowRecording(videoID: String) {
        let removedRecent = deletedRecentVideoIDs.remove(videoID) != nil
        let removedWatchHistory = deletedWatchHistoryVideoIDs.remove(videoID) != nil
        if removedRecent || removedWatchHistory {
            persistDeletedVideoIDs()
        }
    }

    func requestPlayback(videoID: String, time: Double, sourceURL: String?) {
        let request = PlaybackRequest(videoID: videoID, time: time, sourceURL: sourceURL)
        pendingPlaybackRequest = request
        NotificationCenter.default.post(name: .openRecentVideo, object: nil, userInfo: request.userInfo)
    }

    func consumePendingPlaybackRequest() -> PlaybackRequest? {
        let request = pendingPlaybackRequest
        pendingPlaybackRequest = nil
        return request
    }

    func setWatchLaterStars(videoID: String, stars: Int) {
        let clamped = min(5, max(0, stars))
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

    private func persistDeletedVideoIDs() {
        defaults.set(Array(deletedRecentVideoIDs), forKey: Keys.deletedRecentVideoIDs)
        defaults.set(Array(deletedWatchHistoryVideoIDs), forKey: Keys.deletedWatchHistoryVideoIDs)
    }

    func storedHistoryUsageBytes() -> Int {
        let dataBytes = [
            Keys.recentVideos,
            Keys.watchHistoryVideos
        ].reduce(0) { total, key in
            total + (defaults.data(forKey: key)?.count ?? 0)
        }

        let deletedIDBytes = [
            Keys.deletedRecentVideoIDs,
            Keys.deletedWatchHistoryVideoIDs
        ].reduce(0) { total, key in
            guard let strings = defaults.stringArray(forKey: key),
                  let data = try? PropertyListSerialization.data(fromPropertyList: strings, format: .binary, options: 0) else {
                return total
            }
            return total + data.count
        }

        return dataBytes + deletedIDBytes
    }

    static func formatStorageSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func upsertVideo(
        in videos: [RecentVideoItem],
        videoID: String,
        title: String,
        position: Double,
        sourceURL: String?,
        playedAt: Date,
        maxCount: Int
    ) -> [RecentVideoItem] {
        var updated = normalizedVideos(videos, maxCount: maxCount)
        if let index = updated.firstIndex(where: { $0.videoID == videoID }) {
            updated[index].title = title
            updated[index].lastPosition = position
            updated[index].lastPlayedAt = playedAt
            updated[index].sourceURL = sourceURL ?? updated[index].sourceURL
        } else {
            updated.append(RecentVideoItem(videoID: videoID, title: title, lastPosition: position, lastPlayedAt: playedAt, sourceURL: sourceURL))
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
                if video.sourceURL != nil {
                    existing.sourceURL = video.sourceURL
                }
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
                    openVideo(video)
                } label: {
                    HStack(spacing: 10) {
                        AsyncImage(url: StreamingProviderRegistry.shared.thumbnailURL(for: video.videoID)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                        } placeholder: {
                                            Rectangle().fill(Color.gray.opacity(0.25))
                                        }
                                        .frame(width: 96, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(video.title)
                                                .foregroundColor(.accentColor)
                                                .lineLimit(2)
                                            Text("Resume at \(AppSettings.formatPlaybackTime(video.lastPosition))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Open \(video.title)")

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

    private func openVideo(_ video: RecentVideoItem) {
        openWindow(id: "main-player")
        settings.requestPlayback(videoID: video.videoID, time: video.lastPosition, sourceURL: video.sourceURL)
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

            Toggle("Lock 16:9 While Resizing", isOn: $settings.lockAspectRatio16x9Enabled)
        }
    }
}

struct WindowCommandBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openWatchHistory)) { _ in
                openWindow(id: "watch-history")
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
                .background(WindowCommandBridge())
        }
        .commands {
            PlayerCommands(settings: settings)
        }

        Window("Watch History", id: "watch-history") {
            WatchHistoryView()
                .environmentObject(settings)
                .background(WindowCommandBridge())
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
    private var lockAspectRatio16x9Item: NSMenuItem?
    private var recentVideosItem: NSMenuItem?
    private var statisticsItem: NSMenuItem?

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

        let openURLItem = NSMenuItem(title: "Open URL...", action: #selector(openURL), keyEquivalent: "o")
        openURLItem.image = menuIcon("link")
        menu.addItem(openURLItem)

        let watchHistoryItem = NSMenuItem(title: "Open Watch History", action: #selector(openWatchHistory), keyEquivalent: "h")
        watchHistoryItem.keyEquivalentModifierMask = [.command, .shift]
        watchHistoryItem.image = menuIcon("clock.arrow.circlepath")
        menu.addItem(watchHistoryItem)

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

        let statistics = NSMenuItem(title: "Statistics", action: nil, keyEquivalent: "")
        statistics.submenu = NSMenu(title: "Statistics")
        menu.addItem(statistics)
        statisticsItem = statistics
        rebuildStatisticsMenu()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func openURL() {
        NotificationCenter.default.post(name: .openURL, object: nil)
    }

    @objc func openWatchHistory() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openWatchHistory, object: nil)
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

    @objc func toggleLockAspectRatio16x9(_ sender: NSMenuItem) {
        settings.lockAspectRatio16x9Enabled.toggle()
    }

    @objc func openRecentVideoFromMenu(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let videoID = info["videoID"] as? String else { return }
        let time = info["time"] as? Double ?? 0
        settings.requestPlayback(videoID: videoID, time: time, sourceURL: info["sourceURL"] as? String)
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
            playItem.representedObject = PlaybackRequest(videoID: video.videoID, time: video.lastPosition, sourceURL: video.sourceURL).userInfo
            applyThumbnail(to: playItem, videoID: video.videoID)
            submenu.addItem(playItem)
        }

        submenu.addItem(NSMenuItem.separator())
        let clearAllItem = NSMenuItem(title: "Clear Recent Videos", action: #selector(clearRecentVideosFromMenu(_:)), keyEquivalent: "")
        clearAllItem.target = self
        submenu.addItem(clearAllItem)
    }

    private func rebuildStatisticsMenu() {
        guard let submenu = statisticsItem?.submenu else { return }
        submenu.removeAllItems()

        let recentCount = settings.recentVideos.count
        let historyCount = settings.watchHistoryVideos.count
        let usage = AppSettings.formatStorageSize(settings.storedHistoryUsageBytes())

        [
            "Recent Entries: \(recentCount)",
            "Watch History Entries: \(historyCount)",
            "Disk Usage: \(usage)"
        ].forEach { title in
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }
    }

    private func applyThumbnail(to item: NSMenuItem, videoID: String) {
        if let cached = thumbnailCache[videoID] {
            item.image = cached
            return
        }

        guard let url = StreamingProviderRegistry.shared.thumbnailURL(for: videoID) else { return }
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
        let targetSize = NSSize(width: 36, height: 26)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }

    private func menuIcon(_ systemSymbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: nil)
        image?.size = NSSize(width: 16, height: 16)
        image?.isTemplate = true
        return image
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
        observers.append(center.addObserver(forName: .setLockAspectRatio16x9, object: nil, queue: .main) { [weak self] notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                self?.lockAspectRatio16x9Item?.state = enabled ? .on : .off
            }
        })
        observers.append(center.addObserver(forName: .recentVideosUpdated, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildRecentVideosMenu()
            self?.rebuildStatisticsMenu()
        })
        observers.append(center.addObserver(forName: .watchHistoryUpdated, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildStatisticsMenu()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension Notification.Name {
    static let openURL = Notification.Name("openURL")
    static let openWatchHistory = Notification.Name("openWatchHistory")
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
