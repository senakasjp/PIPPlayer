import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import QuickLookThumbnailing
import CryptoKit

// MARK: - Library model

/// A playlist entry: a folder when `children` is non-nil, otherwise a playable item.
struct PlaylistNode: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""                   // folder name, or an item's custom title (empty = default title)
    var url: String?
    var children: [PlaylistNode]?
    var isExpanded = true
    var lastPlayedID: UUID?         // folders: the item playback stopped at, for resuming

    var isFolder: Bool { children != nil }
    var subfolders: [PlaylistNode] { children?.filter(\.isFolder) ?? [] }

    static func folder(_ name: String, _ children: [PlaylistNode] = [], id: UUID = UUID()) -> PlaylistNode {
        PlaylistNode(id: id, name: name, children: children)
    }

    static func item(_ url: String, title: String = "", id: UUID = UUID()) -> PlaylistNode {
        PlaylistNode(id: id, name: title, url: url)
    }

    var media: StreamingMedia? { url.flatMap { StreamingProviderRegistry.shared.resolve($0) } }
    var fileURL: URL? { url.flatMap(URL.init(string:)).flatMap { $0.isFileURL ? $0 : nil } }

    var title: String {
        guard name.isEmpty else { return name }
        return isFolder ? "Untitled Folder" : (media?.defaultTitle ?? "Video")
    }
}

enum PlaylistRepeat: String {
    case off, all, one
}

enum PlaylistLibrary {
    static let key = "playlistLibrary"

    static func load(defaults: UserDefaults = .standard) -> [PlaylistNode] {
        if let data = defaults.data(forKey: key),
           let nodes = try? JSONDecoder().decode([PlaylistNode].self, from: data) {
            return nodes
        }
        return (defaults.stringArray(forKey: "playlistURLs") ?? []).map { .item($0) }
    }

    static func save(_ nodes: [PlaylistNode], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(nodes) {
            defaults.set(data, forKey: key)
        }
    }

    static func mergingMediaFolder(_ discovered: [PlaylistNode], into saved: [PlaylistNode]) -> [PlaylistNode] {
        var knownFiles = Set(saved.items.compactMap { $0.fileURL?.standardizedFileURL })
        var result = saved
        func merge(_ nodes: [PlaylistNode], parent: UUID?) {
            for node in nodes {
                if let children = node.children {
                    if result.node(node.id) != nil {
                        merge(children, parent: node.id)
                    } else {
                        let newItems = children.items.compactMap { $0.fileURL?.standardizedFileURL }
                        guard newItems.contains(where: { !knownFiles.contains($0) }) else { continue }
                        var folder = node
                        folder.children = []
                        result.insert([folder], into: parent)
                        merge(children, parent: folder.id)
                    }
                } else if let file = node.fileURL?.standardizedFileURL, knownFiles.insert(file).inserted {
                    result.insert([node], into: parent)
                }
            }
        }
        merge(discovered, parent: nil)
        return result
    }

    /// Item playback stopped at when playing the whole library.
    static let rootLastPlayedKey = "playlistLastPlayed"
    /// Folder being played ("" = whole library), so queue mode survives relaunch.
    static let scopeKey = "playlistScope"
    static let mediaExtensions: Set<String> = ["mp4", "webm", "mkv"]

    /// The one folder beside the app that's always the playlist — no folder picking needed.
    /// Subfolders inside it become categories.
    static var mediaFolderURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("YouTubePlayer Media", isDirectory: true)
    }

    /// Rebuilds the library straight from `mediaFolderURL`'s current contents.
    static func loadFromMediaFolder() -> [PlaylistNode] {
        let folder = mediaFolderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return contents
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap(node(forFile:))
    }

    /// Deterministic id from a file's path, so resume points survive re-scanning the folder on every launch.
    private static func stableID(for path: String) -> UUID {
        let digest = SHA256.hash(data: Data(path.utf8))
        return NSUUID(uuidBytes: Array(digest.prefix(16))) as UUID
    }

    /// A local video file becomes an item; a directory becomes a folder of its supported videos.
    static func node(forFile file: URL) -> PlaylistNode? {
        let id = stableID(for: file.path)
        if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: file, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            let children = contents
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .compactMap(node(forFile:))
            return children.isEmpty ? nil : .folder(file.lastPathComponent, children, id: id)
        }
        return mediaExtensions.contains(file.pathExtension.lowercased()) ? .item(file.absoluteString, id: id) : nil
    }

    static func m3u(_ items: [PlaylistNode]) -> String {
        items.reduce(into: "#EXTM3U\n") { text, item in
            guard let url = item.url else { return }
            text += "#EXTINF:-1,\(item.title)\n\(item.fileURL?.path ?? url)\n"
        }
    }

    /// Parses M3U/M3U8 text. Relative paths resolve against `base`; unsupported entries are skipped.
    static func parseM3U(_ text: String, relativeTo base: URL) -> [PlaylistNode] {
        var title = ""
        var nodes: [PlaylistNode] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                title = line.split(separator: ",", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let url: String
            if line.contains("://") {
                url = line
            } else {
                url = (line.hasPrefix("/") ? URL(fileURLWithPath: line) : base.appendingPathComponent(line)).absoluteString
            }
            if StreamingProviderRegistry.shared.resolve(url) != nil {
                nodes.append(.item(url, title: title))
            }
            title = ""
        }
        return nodes
    }
}

extension Array where Element == PlaylistNode {
    /// Playable items in tree order.
    var items: [PlaylistNode] { flatMap { $0.children?.items ?? [$0] } }
    var folderCount: Int { reduce(0) { $0 + ($1.isFolder ? 1 + ($1.children?.folderCount ?? 0) : 0) } }

    func node(_ id: UUID) -> PlaylistNode? {
        for node in self {
            if node.id == id { return node }
            if let found = node.children?.node(id) { return found }
        }
        return nil
    }

    /// Parent folder (nil = top level) and index of a node.
    func location(of id: UUID, parent: UUID? = nil) -> (parent: UUID?, index: Int)? {
        for (index, node) in enumerated() {
            if node.id == id { return (parent, index) }
            if let found = node.children?.location(of: id, parent: node.id) { return found }
        }
        return nil
    }

    func contains(_ id: UUID, within ancestor: UUID) -> Bool {
        id == ancestor || node(ancestor)?.children?.node(id) != nil
    }

    mutating func update(_ id: UUID, _ change: (inout PlaylistNode) -> Void) {
        for index in indices {
            if self[index].id == id { return change(&self[index]) }
            self[index].children?.update(id, change)
        }
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> PlaylistNode? {
        if let index = firstIndex(where: { $0.id == id }) { return remove(at: index) }
        for index in indices {
            if let removed = self[index].children?.remove(id) { return removed }
        }
        return nil
    }

    mutating func removeItems(where predicate: (PlaylistNode) -> Bool) {
        removeAll { !$0.isFolder && predicate($0) }
        for index in indices { self[index].children?.removeItems(where: predicate) }
    }

    /// Inserts into a folder (nil = top level) at an index, or at the end.
    mutating func insert(_ nodes: [PlaylistNode], into folder: UUID?, at index: Int? = nil) {
        guard let folder else {
            return insert(contentsOf: nodes, at: Swift.min(index ?? count, count))
        }
        update(folder) { parent in
            let count = parent.children?.count ?? 0
            parent.children?.insert(contentsOf: nodes, at: Swift.min(index ?? count, count))
            parent.isExpanded = true
        }
    }

    /// The playlist item for media that is loading: the preferred item when it matches, else the first match.
    func item(playing mediaID: String, preferring preferred: UUID?) -> PlaylistNode? {
        let matches = items.filter { $0.media?.mediaID == mediaID }
        return matches.first { $0.id == preferred } ?? matches.first
    }

    /// Records the item as the resume point of every folder that contains it.
    mutating func markPlayed(_ id: UUID) {
        for index in indices where self[index].children?.node(id) != nil {
            self[index].lastPlayedID = id
            self[index].children?.markPlayed(id)
        }
    }

    /// Forgets the item as a resume point once its folders finish playing.
    mutating func clearPlayed(_ id: UUID) {
        for index in indices where self[index].children?.node(id) != nil {
            if self[index].lastPlayedID == id { self[index].lastPlayedID = nil }
            self[index].children?.clearPlayed(id)
        }
    }

    mutating func shuffleRecursively() {
        shuffle()
        for index in indices { self[index].children?.shuffleRecursively() }
    }
}

// MARK: - Playlist sheet

private struct PlaylistPanelAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ view: NSView, context: Context) {}
}

struct PlaylistView: View {
    @Binding var library: [PlaylistNode]
    let currentItemID: UUID?
    var onFileTrashed: (URL) -> Void = { _ in }
    /// Plays an item (nil = first item) within a folder scope (nil = whole library).
    let onPlay: (_ item: UUID?, _ scope: UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("playlistRepeat") private var repeatMode = PlaylistRepeat.off
    @State private var selection = Set<UUID>()
    @State private var query = ""
    @State private var panelAnchor = NSView(frame: .zero)
    @State private var newURL = ""
    @State private var errorMessage: String?
    @State private var fileToTrash: URL?
    @State private var showsTrashConfirmation = false
    @State private var showsClearConfirmation = false
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var hoveredID: UUID?
    @State private var openFolder: UUID?        // folder shown in the contents pane; nil = all videos
    @ObservedObject private var metadata = PlaylistMetadata.shared

    private struct Row: Identifiable {
        let node: PlaylistNode
        let depth: Int
        var guides: [Bool] = []     // per ancestor level: whether a tree line continues past this row
        var isLast = true           // last child of its folder (the branch line ends here)
        var number = 1              // position within its folder
        var isResume = false        // where playback stopped in the open folder
        var id: UUID { node.id }
    }

    private static let indent: CGFloat = 18
    private static let rootID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private static let line = Color.white.opacity(0.15)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            addBar
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 360, maxHeight: .infinity)
                detail
                    .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: PlayerChrome.radius))
            .overlay(RoundedRectangle(cornerRadius: PlayerChrome.radius).strokeBorder(.white.opacity(0.06)))
            footer
                .padding(.horizontal, PlayerChrome.padding)
                .frame(height: 38)
                .playerPanel()
        }
        .padding(12)
        .frame(minWidth: 820, idealWidth: 1040, minHeight: 460, idealHeight: 640)
        .background(PlayerChrome.panel.opacity(0.94))
        .background(.ultraThinMaterial)
        .background(WindowCornerRadius())
        .background(CenterOnScreen())
        .background(PlaylistPanelAnchor(view: panelAnchor))
        .foregroundStyle(.white)
        .tint(PlayerChrome.accent)
        .environment(\.colorScheme, .dark)
        .onAppear {
            // Open where playback is.
            openFolder = currentItemID.flatMap { library.location(of: $0)?.parent }
        }
        .confirmationDialog("Move original file to Trash?", isPresented: $showsTrashConfirmation, titleVisibility: .visible) {
            Button("Move Original File to Trash", role: .destructive, action: trashSelectedFile)
            Button("Cancel", role: .cancel) { fileToTrash = nil }
        } message: {
            Text("\(fileToTrash?.lastPathComponent ?? "This file") will be moved from its original folder to the Mac’s Trash and removed from the playlist. You can restore it from Trash.")
        }
        .alert(renameTitle, isPresented: Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename", action: commitRename)
            Button("Cancel", role: .cancel) { renamingID = nil }
        } message: {
            Text(renamingID.flatMap { library.node($0) }?.isFolder == false ? "Leave empty to use the video’s own title." : "")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Playlist").font(.system(size: 17, weight: .semibold))
            Text(summary).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(folderTitle(folderID))", text: $query)
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                    .accessibilityLabel("Search this folder")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
        }
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Paste a YouTube, playlist, MP4, WebM or MKV URL", text: $newURL)
                        .textFieldStyle(.plain)
                        .onSubmit(addURL)
                    PlayerChrome.iconButton("plus.circle.fill", "Add URL", action: addURL)
                        .foregroundStyle(PlayerChrome.accent)
                        .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.leading, 8)
                .frame(height: 28)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
                .padding(.trailing, 6)
                PlayerChrome.iconButton("plus.rectangle.on.folder", "Add files or folders…", action: addFiles)
                PlayerChrome.iconButton("folder.badge.plus", "New folder", action: newFolder)
                Menu {
                    Button("Import M3U Playlist…", action: importM3U)
                    Button("Export \(exportScopeName) as M3U…", action: exportM3U)
                        .disabled(exportItems.isEmpty)
                } label: {
                    Image(systemName: "square.and.arrow.up.on.square")
                        .font(.system(size: PlayerChrome.iconSize, weight: .semibold))
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("Import or export")
                .menuStyle(.borderlessButton)
                .tint(.white)
                .fixedSize()
                .help("Import or export M3U playlists")
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding<UUID?>(get: { folderID ?? Self.rootID },
                                       set: { id in openFolder = id == Self.rootID ? nil : id; query = "" })) {
            sidebarRow(nil, row: nil)
                .tag(Self.rootID)
            Section("Folders") {
                ForEach(sidebarRows) { sidebarRow($0.node, row: $0).tag($0.id) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .contextMenu(forSelectionType: UUID.self, menu: { ids in
            if ids.first != Self.rootID { contextMenu(ids) }
        }) { ids in
            if let id = ids.first { playFolder(id == Self.rootID ? nil : id) }
        }
    }

    private func sidebarRow(_ folder: PlaylistNode?, row: Row?) -> some View {
        let items = folder?.children?.items ?? library.items
        let isPlayingHere = currentItemID.map { id in items.contains { $0.id == id } } ?? false
        return HStack(spacing: 0) {
            if let row {
                treeLines(row)
                disclosure(row)
            }
            Image(systemName: folder == nil ? "square.stack.fill" : (folder!.isExpanded && !folder!.subfolders.isEmpty ? "folder.fill" : "folder"))
                .foregroundStyle(PlayerChrome.accent)
                .frame(width: 20)
                .padding(.trailing, 6)
            Text(folder.map(displayTitle) ?? "All Videos")
                .font(.system(size: 12, weight: folder == nil ? .semibold : .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            if isPlayingHere {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(PlayerChrome.accent)
                    .accessibilityLabel("Playing")
            } else if resumeID(in: folder?.id) != nil {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Remembers where playback stopped")
                    .accessibilityLabel("Has resume point")
            }
            Text("\(items.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 6)
        }
        .frame(height: 24)
        .contentShape(Rectangle())
    }

    /// Folder tree for the sidebar, with connector guides computed among sibling folders.
    private var sidebarRows: [Row] {
        func flatten(_ nodes: [PlaylistNode], _ depth: Int, _ guides: [Bool]) -> [Row] {
            let folders = nodes.filter(\.isFolder)
            return folders.enumerated().flatMap { index, node in
                let isLast = index == folders.count - 1
                let row = Row(node: node, depth: depth, guides: guides, isLast: isLast, number: index + 1)
                guard node.isExpanded else { return [row] }
                return [row] + flatten(node.children ?? [], depth + 1, depth == 0 ? [] : guides + [!isLast])
            }
        }
        return flatten(library, 0, [])
    }

    // MARK: Contents pane

    private var detail: some View {
        VStack(spacing: 0) {
            folderHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            Color.white.opacity(0.06).frame(height: 1)
            content
        }
        .background(Color.black.opacity(0.12))
    }

    private var folderHeader: some View {
        let items = folderID.flatMap { library.node($0)?.children?.items } ?? library.items
        let resume = resumeID(in: folderID).flatMap { library.node($0) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                breadcrumb
                Text(folderSummary(items))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            if let resume {
                Button { onPlay(resume.id, folderID) } label: {
                    Label(resumeLabel(resume), systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(PlayerChrome.accent, in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: 320)
                .help("Continue where playback stopped in this folder")
                PlayerChrome.iconButton("backward.end.alt.fill", "Play from the beginning") { playFolder(folderID, fromStart: true) }
                    .disabled(items.isEmpty)
            } else {
                Button { playFolder(folderID) } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 24)
                        .background(PlayerChrome.accent, in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(items.isEmpty)
            }
        }
    }

    /// All Videos › Folder › Subfolder, each segment clickable.
    private var breadcrumb: some View {
        var path: [PlaylistNode] = []
        var cursor = folderID
        while let id = cursor, let node = library.node(id) {
            path.insert(node, at: 0)
            cursor = library.location(of: id)?.parent
        }
        return HStack(spacing: 6) {
            crumb("All Videos", id: nil, isLast: path.isEmpty)
            ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                crumb(displayTitle(node), id: node.id, isLast: index == path.count - 1)
            }
        }
    }

    private func crumb(_ title: String, id: UUID?, isLast: Bool) -> some View {
        Button { openFolder = id; query = "" } label: {
            Text(title)
                .font(.system(size: isLast ? 14 : 12, weight: isLast ? .semibold : .medium))
                .foregroundStyle(isLast ? .white : .white.opacity(0.6))
                .lineLimit(1)
        }
        .buttonStyle(.borderless)
        .disabled(isLast)
    }

    private func resumeLabel(_ item: PlaylistNode) -> String {
        let at = savedPosition(item).map { " at \(Self.formatDuration($0))" } ?? ""
        return "Continue “\(displayTitle(item))”\(at)"
    }

    private func folderSummary(_ items: [PlaylistNode]) -> String {
        var parts = [items.count == 1 ? "1 video" : "\(items.count) videos"]
        let subfolders = (folderID.flatMap { library.node($0)?.subfolders } ?? library.filter(\.isFolder)).count
        if subfolders > 0 { parts.append(subfolders == 1 ? "1 folder" : "\(subfolders) folders") }
        let total = items.compactMap { duration($0, info: $0.url.flatMap { metadata.info[$0] }) }.reduce(0, +)
        if total > 0 { parts.append(Self.formatDuration(total)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        let rows = visibleRows
        if library.isEmpty {
            placeholder("text.badge.plus", "Your playlist is empty",
                        "Add video links, MP4/WebM/MKV files or whole folders.\nCreate folders to organize them.")
        } else if rows.isEmpty {
            if query.isEmpty {
                placeholder("folder", "This folder is empty", "Add links or files while this folder is open,\nor use Move To on other videos.")
            } else {
                placeholder("magnifyingglass", "No matches", "No videos match “\(query)”.")
            }
        } else {
            ScrollViewReader { proxy in
                List(selection: $selection) {
                    ForEach(rows) { row($0) }
                        .onMove(perform: query.isEmpty ? moveRows : nil)
                }
                .onAppear { scrollToResume(rows, proxy) }
                .onChange(of: openFolder) { _ in scrollToResume(visibleRows, proxy) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .contextMenu(forSelectionType: UUID.self, menu: contextMenu) { ids in
                guard let id = ids.first, let node = library.node(id) else { return }
                if node.isFolder { openFolder = id; query = "" } else { play(id) }
            }
            .onDeleteCommand(perform: removeSelection)
        }
    }

    /// Brings the video where playback stopped into view when a folder opens.
    private func scrollToResume(_ rows: [Row], _ proxy: ScrollViewProxy) {
        guard let target = rows.first(where: \.isResume)?.id else { return }
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
    }

    private func placeholder(_ symbol: String, _ title: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Text(title).font(.headline)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            PlayerChrome.iconButton("play.fill", "Play \(folderTitle(folderID))") { playFolder(folderID) }
                .disabled((folderID.flatMap { library.node($0)?.children?.items } ?? library.items).isEmpty)
            PlayerChrome.iconButton(repeatMode == .one ? "repeat.1" : "repeat", repeatHelp, action: cycleRepeat)
                .foregroundStyle(repeatMode == .off ? Color.white : PlayerChrome.accent)
            Menu {
                Button("Shuffle all videos") { library.shuffleRecursively() }
                Button("Shuffle remaining videos", action: shuffleRemaining)
                    .disabled(remainingSiblings.count < 2)
            } label: {
                Image(systemName: "shuffle").font(.system(size: PlayerChrome.iconSize, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .tint(.white)
            .accessibilityLabel("Shuffle")
            .disabled(library.items.count < 2)
            .help("Randomize the playlist order")
            Divider().frame(height: 18).padding(.horizontal, 6)
            PlayerChrome.iconButton("arrow.up", "Move selection up") { move(by: -1) }
                .disabled(!canMove(by: -1))
            PlayerChrome.iconButton("arrow.down", "Move selection down") { move(by: 1) }
                .disabled(!canMove(by: 1))
            PlayerChrome.iconButton("minus", "Remove selection from playlist (⌫)", action: removeSelection)
                .disabled(selection.isEmpty)
            Spacer()
            Button("Clear…") { showsClearConfirmation = true }
                .disabled(library.isEmpty)
                .confirmationDialog("Clear the entire playlist?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                    Button("Clear Playlist", role: .destructive) { library.removeAll(); selection.removeAll() }
                } message: {
                    Text("All videos and folders are removed from the playlist. Original files are not affected.")
                }
            Button { dismiss() } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
                    .background(PlayerChrome.accent, in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(.defaultAction)
        }
        .buttonStyle(.borderless)
    }

    // MARK: Rows

    private func row(_ row: Row) -> some View {
        let node = row.node
        let isCurrent = node.id == currentItemID
        let isResume = row.isResume && !isCurrent
        let isChecked = selection.contains(node.id)
        let info = node.url.flatMap { metadata.info[$0] }
        return HStack(spacing: 0) {
            Button {
                if isChecked { selection.remove(node.id) } else { selection.insert(node.id) }
            } label: {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(isChecked ? PlayerChrome.accent : .white.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Select \(displayTitle(node))")
            .accessibilityValue(isChecked ? "Selected" : "Not selected")
            Text("\(row.number).")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 26, alignment: .trailing)
                .padding(.trailing, 8)
            thumbnail(node, info: info, isCurrent: isCurrent, isResume: isResume)
                .padding(.trailing, 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle(node))
                    .font(.system(size: 13, weight: node.isFolder ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? PlayerChrome.accent : .white)
                    .lineLimit(1)
                ((isResume
                    ? Text("Stopped here · ").foregroundColor(PlayerChrome.accent)
                    : Text(""))
                    + Text(subtitle(node, info: info)).foregroundColor(.white.opacity(0.6)))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 12)
            if let file = node.fileURL, !FileManager.default.fileExists(atPath: file.path) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .padding(.trailing, 10)
                    .help("File not found. Its drive may be disconnected.")
                    .accessibilityLabel("File not found")
            }
            if isResume {
                Button { play(node.id) } label: {
                    Label(savedPosition(node).map { "Resume \(Self.formatDuration($0))" } ?? "Resume", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(PlayerChrome.accent, in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .padding(.trailing, 8)
                .help("Continue from where playback stopped")
                .accessibilityLabel("Resume \(displayTitle(node))")
            }
            qualityBadge(info)
                .frame(width: 32)
            formatColumn(node, info: info)
                .frame(width: 136, alignment: .leading)
            let seconds = duration(node, info: info)
            Text(seconds.map(Self.formatDuration) ?? "--:--")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(seconds == nil ? 0.3 : 0.8))
                .accessibilityLabel(seconds == nil ? "Duration unknown" : "Duration \(seconds.map(Self.formatDuration) ?? "")")
                .frame(width: 56, alignment: .trailing)
                .padding(.trailing, 8)
            Menu { moveMenuItems([node.id]) } label: {
                Image(systemName: "plus.square.on.square").font(.system(size: 13, weight: .regular))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 26)
            .tint(.white)
            .help("Add to folder")
            .accessibilityLabel("Move \(displayTitle(node)) to a folder")
            Menu { contextMenu([node.id]) } label: {
                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 15, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 26)
            .tint(.white)
            .help("More")
            .accessibilityLabel("More actions for \(displayTitle(node))")
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) { Color.white.opacity(0.06).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? node.id : (hoveredID == node.id ? nil : hoveredID) }
        .task(id: node.url) { if let url = node.url { await metadata.load(url) } }
        .help(node.url ?? displayTitle(node))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 6))
        .listRowBackground(
            Rectangle().fill(isCurrent ? PlayerChrome.accent.opacity(0.16)
                             : isResume ? PlayerChrome.accent.opacity(0.09)
                             : hoveredID == node.id ? Color.white.opacity(0.04) : Color.clear)
        )
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder private func disclosure(_ row: Row) -> some View {
        let node = row.node
        if !node.subfolders.isEmpty {
            Button {
                library.update(node.id) { $0.isExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(node.isExpanded ? 90 : 0))
                    .frame(width: Self.indent, height: 28)
                    .contentShape(Rectangle())
            }
            .frame(maxHeight: .infinity)
            .background {
                // Trunk from an open folder down to its first child.
                if node.isExpanded, !node.subfolders.isEmpty {
                    Canvas { context, size in
                        context.fill(Path(CGRect(x: size.width / 2, y: size.height / 2 + 9, width: 1, height: size.height / 2 - 9)), with: .color(Self.line))
                    }
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(node.isExpanded ? "Collapse \(node.title)" : "Expand \(node.title)")
        } else {
            // Leaf: the branch runs into the row.
            Self.line.frame(width: row.depth > 0 ? Self.indent / 2 : 0, height: 1)
                .frame(width: Self.indent, alignment: .leading)
        }
    }

    /// 16:9 artwork; clicking it plays. Shows saved progress along the bottom edge.
    private func thumbnail(_ node: PlaylistNode, info: PlaylistMetadata.Info?, isCurrent: Bool, isResume: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: PlayerChrome.smallRadius)
        let progress = self.progress(node, info: info)
        return Button { play(node.id) } label: {
            ZStack {
                shape.fill(node.isFolder ? PlayerChrome.accent.opacity(0.18) : Color.white.opacity(0.06))
                if let image = info?.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: placeholderSymbol(node))
                        .font(.system(size: 13))
                        .foregroundStyle(node.isFolder ? PlayerChrome.accent : .white.opacity(0.45))
                }
                if isCurrent || isResume || hoveredID == node.id {
                    Color.black.opacity(0.45)
                    Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCurrent ? PlayerChrome.accent : .white)
                }
            }
            .frame(width: 56, height: 32)
            .clipShape(shape)
            .overlay(alignment: .bottomLeading) {
                if let progress, progress > 0.01 {
                    PlayerChrome.accent.frame(width: 56 * min(progress, 1), height: 2)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(node.isFolder && (node.children ?? []).items.isEmpty)
        .help(node.isFolder ? "Play folder" : isResume ? "Resume" : "Play")
        .accessibilityLabel(node.isFolder ? "Play folder \(displayTitle(node))" : "Play \(displayTitle(node))")
    }

    private func placeholderSymbol(_ node: PlaylistNode) -> String {
        if node.isFolder { return node.isExpanded ? "folder.fill" : "folder" }
        if node.media?.mediaID.hasPrefix("youtube-playlist:") == true { return "list.and.film" }
        if node.media?.providerID == "youtube" { return "play.rectangle.fill" }
        return node.fileURL == nil ? "link" : "film"
    }

    @ViewBuilder private func qualityBadge(_ info: PlaylistMetadata.Info?) -> some View {
        if let label = info?.qualityLabel {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(PlayerChrome.panel)
                .padding(.horizontal, 4)
                .frame(height: 16)
                .background(PlayerChrome.accent.opacity(0.9), in: RoundedRectangle(cornerRadius: PlayerChrome.smallRadius))
                .accessibilityLabel(label == "HD" ? "High definition" : label)
        }
    }

    private func formatColumn(_ node: PlaylistNode, info: PlaylistMetadata.Info?) -> some View {
        HStack(spacing: 8) {
            if let format = format(for: node) {
                Text(format)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .overlay(RoundedRectangle(cornerRadius: PlayerChrome.smallRadius).strokeBorder(.white.opacity(0.5)))
                    .fixedSize()
            }
            if let specs = info?.specs {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(specs, id: \.self) { Text($0) }
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            }
        }
    }

    private func format(for node: PlaylistNode) -> String? {
        if node.isFolder { return nil }
        guard let media = node.media else { return "UNSUPPORTED" }
        if let file = node.fileURL ?? URL(string: node.url ?? ""),
           PlaylistLibrary.mediaExtensions.contains(file.pathExtension.lowercased()) {
            return file.pathExtension.uppercased()
        }
        return media.mediaID.hasPrefix("youtube-playlist:") ? "PLAYLIST" : media.providerName.uppercased()
    }

    private func displayTitle(_ node: PlaylistNode) -> String {
        if node.name.isEmpty, let title = node.url.flatMap({ metadata.info[$0]?.title }) { return title }
        return node.title
    }

    private func subtitle(_ node: PlaylistNode, info: PlaylistMetadata.Info?) -> String {
        if let children = node.children {
            let count = children.items.count
            var text = count == 1 ? "1 video" : "\(count) videos"
            if let stopped = resumeID(in: node.id).flatMap({ library.node($0) }) { text += " · Stopped at \(displayTitle(stopped))" }
            return text
        }
        var parts: [String] = []
        if !query.isEmpty, let parent = library.location(of: node.id)?.parent.flatMap({ library.node($0) }) {
            parts.append(parent.title)
        }
        if let author = info?.author {
            parts.append(author)
        } else if let file = node.fileURL {
            parts.append(file.deletingLastPathComponent().lastPathComponent)
        } else if let host = node.url.flatMap(URL.init(string:))?.host {
            parts.append(host)
        }
        return parts.joined(separator: " · ")
    }

    private func duration(_ node: PlaylistNode, info: PlaylistMetadata.Info?) -> Double? {
        if let children = node.children {
            let known = children.items.compactMap { item in duration(item, info: item.url.flatMap { metadata.info[$0] }) }
            return known.isEmpty ? nil : known.reduce(0, +)
        }
        if let seconds = info?.duration { return seconds }
        guard let id = node.media?.mediaID else { return nil }
        return (UserDefaults.standard.dictionary(forKey: PlaylistMetadata.durationsKey) as? [String: Double])?[id]
    }

    private func progress(_ node: PlaylistNode, info: PlaylistMetadata.Info?) -> Double? {
        guard let id = node.media?.mediaID, let total = duration(node, info: info), total > 0,
              let position = savedPositions[id]
        else { return nil }
        return position / total
    }

    static func formatDuration(_ time: Double) -> String {
        let seconds = Int(max(time, 0).rounded())
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Tree connectors (sidebar): a continuing line per ancestor level, then this row's ├ or └ branch.
    private func treeLines(_ row: Row) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.guides.enumerated()), id: \.offset) { _, continues in
                Canvas { context, size in
                    guard continues else { return }
                    context.fill(Path(CGRect(x: size.width / 2, y: 0, width: 1, height: size.height)), with: .color(Self.line))
                }
                .frame(width: Self.indent)
            }
            if row.depth > 0 {
                Canvas { context, size in
                    let x = size.width / 2, mid = size.height / 2
                    context.fill(Path(CGRect(x: x, y: 0, width: 1, height: row.isLast ? mid : size.height)), with: .color(Self.line))
                    context.fill(Path(CGRect(x: x, y: mid, width: size.width - x, height: 1)), with: .color(Self.line))
                }
                .frame(width: Self.indent)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func contextMenu(_ ids: Set<UUID>) -> some View {
        let nodes = ids.compactMap { library.node($0) }
        if let node = nodes.first, nodes.count == 1 {
            if node.isFolder {
                Button(resumeID(in: node.id) == nil ? "Play Folder" : "Continue Playing Folder") { playFolder(node.id) }
                Button("Play from Beginning") { playFolder(node.id, fromStart: true) }
                Button("Open") { openFolder = node.id; query = "" }
            } else {
                Button("Play") { play(node.id) }
            }
            Button("Rename…") { beginRename(node) }
            if let url = node.url {
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
            }
            if let file = node.fileURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            Divider()
        }
        if !nodes.isEmpty {
            Menu("Move To") { moveMenuItems(ids) }
            Button("New Folder with Selection") { groupIntoFolder(ids) }
            Divider()
            Button("Remove from Playlist") { remove(ids) }
            if let file = nodes.first?.fileURL, nodes.count == 1 {
                Button("Move Original File to Trash…") { fileToTrash = file; showsTrashConfirmation = true }
            }
        }
    }

    @ViewBuilder private func moveMenuItems(_ ids: Set<UUID>) -> some View {
        Button("Top Level") { move(ids, into: nil) }
        ForEach(folderChoices(excluding: ids), id: \.node.id) { choice in
            Button(String(repeating: "    ", count: choice.depth) + choice.node.title) { move(ids, into: choice.node.id) }
        }
        Divider()
        Button("New Folder…") { groupIntoFolder(ids) }
    }

    // MARK: Derived state

    /// Contents of the open folder, or matching videos anywhere inside it while searching.
    private var visibleRows: [Row] {
        let children = folderID.flatMap { library.node($0)?.children } ?? library
        let needle = query.trimmingCharacters(in: .whitespaces)
        let nodes = needle.isEmpty ? children : children.items.filter {
            displayTitle($0).localizedCaseInsensitiveContains(needle) || ($0.url ?? "").localizedCaseInsensitiveContains(needle)
        }
        let resume = resumeID(in: folderID)
        return nodes.enumerated().map { Row(node: $1, depth: 0, number: $0 + 1, isResume: $1.id == resume) }
    }

    /// The open folder, if it still exists.
    private var folderID: UUID? {
        openFolder.flatMap { library.node($0)?.isFolder == true ? $0 : nil }
    }

    private func folderTitle(_ id: UUID?) -> String {
        id.flatMap { library.node($0) }.map(displayTitle) ?? "All Videos"
    }

    /// Where playback stopped in a folder (nil = whole library), if that item is still inside it.
    private func resumeID(in folder: UUID?) -> UUID? {
        let items = folder.flatMap { library.node($0)?.children?.items } ?? library.items
        let id = folder == nil
            ? UserDefaults.standard.string(forKey: PlaylistLibrary.rootLastPlayedKey).flatMap(UUID.init(uuidString:))
            : library.node(folder!)?.lastPlayedID
        if let id, items.contains(where: { $0.id == id }) { return id }
        // ponytail: folders played before resume points existed fall back to the first partly
        // watched video; store play timestamps if the most recent one matters.
        let positions = savedPositions
        return items.first { item in
            guard let mediaID = item.media?.mediaID, let position = positions[mediaID], position >= 1 else { return false }
            return duration(item, info: item.url.flatMap { metadata.info[$0] }).map { position < $0 - 5 } ?? true
        }?.id
    }

    private var savedPositions: [String: Double] {
        UserDefaults.standard.dictionary(forKey: "lastPlaybackPositions") as? [String: Double] ?? [:]
    }

    private func savedPosition(_ node: PlaylistNode) -> Double? {
        node.media.flatMap { savedPositions[$0.mediaID] }.flatMap { $0 >= 1 ? $0 : nil }
    }

    private var summary: String {
        let videos = library.items.count
        let folders = library.folderCount
        var parts = [videos == 1 ? "1 video" : "\(videos) videos"]
        if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders) folders") }
        let total = library.items.compactMap { duration($0, info: $0.url.flatMap { metadata.info[$0] }) }.reduce(0, +)
        if total > 0 { parts.append(Self.formatDuration(total)) }
        if let current = currentItemID.flatMap({ library.node($0) }) { parts.append("Now playing: \(displayTitle(current))") }
        return parts.joined(separator: " · ")
    }

    private var exportFolder: PlaylistNode? { folderID.flatMap { library.node($0) } }
    private var exportScopeName: String { exportFolder.map { "“\($0.title)”" } ?? "Playlist" }
    private var exportItems: [PlaylistNode] { exportFolder?.children?.items ?? library.items }

    private var renameTitle: String {
        renamingID.flatMap { library.node($0) }?.isFolder == true ? "Rename Folder" : "Rename Video"
    }

    private var repeatHelp: String {
        switch repeatMode {
        case .off: return "Repeat is off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
        }
    }

    private func folderChoices(excluding ids: Set<UUID>) -> [Row] {
        func walk(_ nodes: [PlaylistNode], _ depth: Int) -> [Row] {
            nodes.filter { $0.isFolder && !ids.contains($0.id) }.flatMap { [Row(node: $0, depth: depth)] + walk($0.children ?? [], depth + 1) }
        }
        return walk(library, 0)
    }

    /// Items after the current one in its own folder.
    private var remainingSiblings: ArraySlice<PlaylistNode> {
        guard let currentItemID, let location = library.location(of: currentItemID) else { return [] }
        let siblings = location.parent.flatMap { library.node($0)?.children } ?? library
        return siblings[(location.index + 1)...]
    }

    // MARK: Actions

    private func play(_ id: UUID) {
        guard let node = library.node(id) else { return }
        if node.isFolder {
            playFolder(id)
        } else {
            onPlay(id, library.location(of: id)?.parent)
        }
    }

    /// Plays a folder (nil = whole library), continuing where it stopped unless asked to start over.
    private func playFolder(_ folder: UUID?, fromStart: Bool = false) {
        onPlay(fromStart ? nil : resumeID(in: folder), folder)
    }

    private func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off
    }

    private func add(_ nodes: [PlaylistNode]) {
        library.insert(nodes, into: folderID)
        errorMessage = nil
    }

    private func addURL() {
        let input = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        guard StreamingProviderRegistry.shared.resolve(input) != nil else {
            errorMessage = "Enter a supported video or playlist URL, or choose an MP4, WebM or MKV file."
            return
        }
        add([.item(input)])
        newURL = ""
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .folder] + PlaylistLibrary.mediaExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose videos, or folders to add as playlist folders."
        panel.prompt = "Add to Playlist"
        presentPanel(panel) { response in
            guard response == .OK else { return }
            let nodes = panel.urls.compactMap(PlaylistLibrary.node(forFile:))
            if nodes.isEmpty {
                errorMessage = "No MP4, WebM or MKV files were found in the selection."
            } else {
                add(nodes)
            }
        }
    }

    private func presentPanel(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let owner = panelAnchor.window
        NSApp.activate(ignoringOtherApps: true)
        if let owner {
            owner.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: owner, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func newFolder() {
        let folder = PlaylistNode.folder("New Folder")
        add([folder])
        selection = [folder.id]
        beginRename(folder)
    }

    private func groupIntoFolder(_ ids: Set<UUID>) {
        let ordered = visibleRows.map(\.id).filter(ids.contains)
        guard let first = ordered.first, let location = library.location(of: first) else { return }
        let nodes = ordered.compactMap { library.remove($0) }
        let folder = PlaylistNode.folder("New Folder", nodes)
        library.insert([folder], into: location.parent, at: location.index)
        selection = [folder.id]
        beginRename(folder)
    }

    private func beginRename(_ node: PlaylistNode) {
        renameText = node.name
        renamingID = node.id
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        library.update(id) { node in
            if !node.isFolder || !name.isEmpty { node.name = name }
        }
        renamingID = nil
    }

    private func removeSelection() { remove(selection) }

    private func remove(_ ids: Set<UUID>) {
        for id in ids { library.remove(id) }
        selection.subtract(ids)
    }

    private func move(_ ids: Set<UUID>, into folder: UUID?) {
        // Never move a folder into itself or its own subfolders.
        if let folder, ids.contains(where: { library.contains(folder, within: $0) }) { return }
        let ordered = visibleRows.map(\.id).filter(ids.contains) + ids.filter { id in !visibleRows.contains { $0.id == id } }
        let nodes = ordered.compactMap { library.remove($0) }
        library.insert(nodes, into: folder)
    }

    /// Drag reordering inside the open folder.
    private func moveRows(from source: IndexSet, to destination: Int) {
        if let folderID {
            library.update(folderID) { $0.children?.move(fromOffsets: source, toOffset: destination) }
        } else {
            library.move(fromOffsets: source, toOffset: destination)
        }
    }

    private func canMove(by offset: Int) -> Bool {
        guard selection.count == 1, let id = selection.first, let location = library.location(of: id) else { return false }
        let count = location.parent.flatMap { library.node($0)?.children?.count } ?? library.count
        return (0..<count).contains(location.index + offset)
    }

    private func move(by offset: Int) {
        guard canMove(by: offset), let id = selection.first, let location = library.location(of: id),
              let node = library.remove(id) else { return }
        library.insert([node], into: location.parent, at: location.index + offset)
    }

    private func shuffleRemaining() {
        guard let currentItemID, let location = library.location(of: currentItemID) else { return }
        func shuffleTail(_ nodes: inout [PlaylistNode]) {
            let start = location.index + 1
            nodes.replaceSubrange(start..., with: nodes[start...].shuffled())
        }
        if let parent = location.parent {
            library.update(parent) { shuffleTail(&$0.children!) }
        } else {
            shuffleTail(&library)
        }
    }

    private func importM3U() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Import"
        presentPanel(panel) { response in
            guard response == .OK, let file = panel.url else { return }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                errorMessage = "Could not read \(file.lastPathComponent)."
                return
            }
            let items = PlaylistLibrary.parseM3U(text, relativeTo: file.deletingLastPathComponent())
            if items.isEmpty {
                errorMessage = "\(file.lastPathComponent) has no supported videos."
            } else {
                add([.folder(file.deletingPathExtension().lastPathComponent, items)])
            }
        }
    }

    private func exportM3U() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u") ?? .plainText]
        panel.nameFieldStringValue = (exportFolder?.title ?? "Playlist") + ".m3u"
        presentPanel(panel) { response in
            guard response == .OK, let file = panel.url else { return }
            do {
                try PlaylistLibrary.m3u(exportItems).write(to: file, atomically: true, encoding: .utf8)
                errorMessage = nil
            } catch {
                errorMessage = "Could not export: \(error.localizedDescription)"
            }
        }
    }

    private func trashSelectedFile() {
        guard let file = fileToTrash else { return }
        fileToTrash = nil
        do {
            try Self.trashOriginalFile(at: file)
            library.removeItems { $0.fileURL?.standardizedFileURL == file.standardizedFileURL }
            onFileTrashed(file)
            errorMessage = nil
        } catch {
            errorMessage = "Could not move \(file.lastPathComponent) to Trash: \(error.localizedDescription)"
        }
    }

    static func trashOriginalFile(at file: URL) throws {
        guard file.isFileURL,
              PlaylistLibrary.mediaExtensions.contains(file.pathExtension.lowercased()),
              try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        try FileManager.default.trashItem(at: file, resultingItemURL: nil)
    }
}

// MARK: - Metadata

/// Artwork, titles and technical details for playlist rows, loaded lazily and kept for the session.
@MainActor
final class PlaylistMetadata: ObservableObject {
    static let shared = PlaylistMetadata()
    /// Durations reported by the player, keyed by media ID (covers YouTube, WebM and MKV).
    static let durationsKey = "mediaDurations"

    struct Info {
        var title: String?
        var author: String?
        var thumbnail: NSImage?
        var duration: Double?
        var size: CGSize?
        var codec: String?
        var frameRate: Float?

        var qualityLabel: String? {
            guard let height = size.map({ min($0.width, $0.height) }) else { return nil }
            return height >= 2160 ? "4K" : height >= 720 ? "HD" : nil
        }

        var specs: [String]? {
            var lines: [String] = []
            if let size { lines.append("\(Int(size.width))×\(Int(size.height))") }
            let detail = [codec, frameRate.map { "\(Int($0.rounded())) fps" }].compactMap { $0 }.joined(separator: " · ")
            if !detail.isEmpty { lines.append(detail) }
            return lines.isEmpty ? nil : lines
        }
    }

    @Published private(set) var info: [String: Info] = [:]
    private var requested = Set<String>()

    func load(_ url: String) async {
        guard requested.insert(url).inserted, let media = StreamingProviderRegistry.shared.resolve(url) else { return }
        var result = Info()
        if media.playbackURL.isFileURL {
            let file = media.playbackURL
            let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: 144, height: 80),
                                                       scale: 2, representationTypes: .thumbnail)
            result.thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            if file.pathExtension.lowercased() == "mp4" { await loadAsset(file, into: &result) }
        } else if media.providerID == "youtube" {
            await loadYouTube(url, media: media, into: &result)
        }
        info[url] = result
    }

    private func loadAsset(_ file: URL, into result: inout Info) async {
        let asset = AVURLAsset(url: file)
        guard let (duration, tracks) = try? await asset.load(.duration, .tracks) else { return }
        if duration.seconds.isFinite, duration.seconds > 0 { result.duration = duration.seconds }
        guard let video = tracks.first(where: { $0.mediaType == .video }),
              let (size, transform, rate, formats) = try? await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        else { return }
        let oriented = size.applying(transform)
        result.size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        if rate > 0 { result.frameRate = rate }
        if let format = formats.first { result.codec = Self.codecName(CMFormatDescriptionGetMediaSubType(format)) }
    }

    /// Title, channel and artwork from YouTube's public oEmbed endpoint.
    private func loadYouTube(_ url: String, media: StreamingMedia, into result: inout Info) async {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: url), URLQueryItem(name: "format", value: "json")]
        if let endpoint = components?.url,
           let (data, _) = try? await URLSession.shared.data(from: endpoint),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result.title = json["title"] as? String
            result.author = json["author_name"] as? String
        }
        if let artwork = StreamingProviderRegistry.shared.thumbnailURL(for: media.mediaID),
           let (data, _) = try? await URLSession.shared.data(from: artwork) {
            result.thumbnail = NSImage(data: data)
        }
    }

    static func codecName(_ code: FourCharCode) -> String {
        let fourCC = String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? ""
        switch fourCC {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "av01": return "AV1"
        case "vp09": return "VP9"
        case "ap4h", "apch", "apcn", "apcs", "apco": return "ProRes"
        default: return fourCC.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    /// Remembers a duration the player reported so the playlist can show it.
    static func recordDuration(_ duration: Double, for mediaID: String) {
        guard duration.isFinite, duration > 0 else { return }
        var durations = UserDefaults.standard.dictionary(forKey: durationsKey) as? [String: Double] ?? [:]
        guard abs((durations[mediaID] ?? 0) - duration) >= 1 else { return }
        durations[mediaID] = duration
        UserDefaults.standard.set(durations, forKey: durationsKey)
    }
}
