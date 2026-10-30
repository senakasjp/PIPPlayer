import Foundation

struct StreamingMedia: Hashable {
    let providerID: String
    let providerName: String
    let mediaID: String
    let playbackURL: URL
    let defaultTitle: String
    let canResumeWithURLParameter: Bool
}

protocol StreamingProvider {
    var id: String { get }
    var displayName: String { get }

    func resolve(_ input: String, startTime: Int?) -> StreamingMedia?
    func playbackURL(for mediaID: String, startTime: Int?) -> URL?
    func thumbnailURL(for mediaID: String) -> URL?
}

struct YouTubeProvider: StreamingProvider {
    let id = "youtube"
    let displayName = "YouTube"

    func resolve(_ input: String, startTime: Int?) -> StreamingMedia? {
        if let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
           supports(url),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let playlistID = components.queryItems?.first(where: { $0.name == "list" })?.value,
           !playlistID.isEmpty {
            if let startTime, startTime > 0 {
                var items = components.queryItems ?? []
                items.removeAll { $0.name == "t" }
                items.append(URLQueryItem(name: "t", value: String(startTime)))
                components.queryItems = items
            }
            return StreamingMedia(providerID: id, providerName: displayName,
                                  mediaID: "youtube-playlist:" + playlistID,
                                  playbackURL: components.url ?? url,
                                  defaultTitle: "YouTube Playlist", canResumeWithURLParameter: true)
        }
        guard let videoID = extractVideoID(from: input),
              let url = playbackURL(for: videoID, startTime: startTime) else { return nil }
        return StreamingMedia(
            providerID: id,
            providerName: displayName,
            mediaID: videoID,
            playbackURL: url,
            defaultTitle: "YouTube Video",
            canResumeWithURLParameter: true
        )
    }

    func playbackURL(for mediaID: String, startTime: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        let isPlaylist = mediaID.hasPrefix("youtube-playlist:")
        components.path = isPlaylist ? "/playlist" : "/watch"
        var queryItems = [URLQueryItem(name: isPlaylist ? "list" : "v",
                                      value: isPlaylist ? String(mediaID.dropFirst("youtube-playlist:".count)) : mediaID)]
        if let startTime, startTime > 0 {
            queryItems.append(URLQueryItem(name: "t", value: "\(startTime)"))
        }
        components.queryItems = queryItems
        return components.url
    }

    func thumbnailURL(for mediaID: String) -> URL? {
        guard !mediaID.hasPrefix("youtube-playlist:") else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(mediaID)/mqdefault.jpg")
    }

    private func supports(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return false }
        let host = url.host?.lowercased() ?? ""
        return ["youtube.com", "youtube-nocookie.com", "youtu.be"].contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    /// Video ID from any common YouTube link shape: watch, share (youtu.be),
    /// embed, Shorts, live, and the legacy /v/ path.
    private func extractVideoID(from input: String) -> String? {
        guard let url = URL(string: input), supports(url) else { return nil }
        let host = url.host?.lowercased() ?? ""

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            guard let last = url.pathComponents.dropFirst().first,
                  !last.isEmpty, last != "/" else { return nil }
            return last
        }

        // Watch URL: youtube.com/watch?v=VIDEO_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !videoID.isEmpty {
            return videoID
        }

        // Path-based URLs: /embed/ID, /shorts/ID, /live/ID, /v/ID.
        let parts = url.pathComponents.filter { $0 != "/" }
        let pathPrefixes = ["embed", "shorts", "live", "v", "e"]
        for (index, part) in parts.enumerated() where pathPrefixes.contains(part.lowercased()) {
            guard index + 1 < parts.count else { continue }
            let id = parts[index + 1]
            if !id.isEmpty, id != "/" { return id }
        }

        return nil
    }
}

struct DisneyPlusProvider: StreamingProvider {
    let id = "disneyplus"
    let displayName = "Disney+"

    func resolve(_ input: String, startTime: Int?) -> StreamingMedia? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), supports(url) else { return nil }
        let mediaID = Self.mediaID(for: url)
        return StreamingMedia(
            providerID: id,
            providerName: displayName,
            mediaID: mediaID,
            playbackURL: url,
            defaultTitle: "Disney+ Video",
            canResumeWithURLParameter: false
        )
    }

    func playbackURL(for mediaID: String, startTime: Int?) -> URL? {
        guard mediaID.hasPrefix("\(id):") else { return nil }
        let path = String(mediaID.dropFirst(id.count + 1))
        guard path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
        return URL(string: "https://www.disneyplus.com\(path)")
    }

    func thumbnailURL(for mediaID: String) -> URL? {
        nil
    }

    private func supports(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return false }
        let host = url.host?.lowercased() ?? ""
        return host == "disneyplus.com" || host.hasSuffix(".disneyplus.com")
    }

    private static func mediaID(for url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        return "disneyplus:\(path)"
    }
}

struct VideoFileProvider: StreamingProvider {
    let id: String
    var displayName: String { id == "webm" ? "WebM" : id.uppercased() }

    func resolve(_ input: String, startTime: Int?) -> StreamingMedia? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["file", "https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.pathExtension.lowercased() == id,
              url.isFileURL || url.host != nil else { return nil }
        return StreamingMedia(providerID: id, providerName: displayName,
                              mediaID: id + ":" + url.absoluteString, playbackURL: url,
                              defaultTitle: url.deletingPathExtension().lastPathComponent,
                              canResumeWithURLParameter: false)
    }

    func playbackURL(for mediaID: String, startTime: Int?) -> URL? {
        guard mediaID.hasPrefix(id + ":") else { return nil }
        return resolve(String(mediaID.dropFirst(id.count + 1)), startTime: nil)?.playbackURL
    }

    func thumbnailURL(for mediaID: String) -> URL? { nil }
}

struct StreamingProviderRegistry {
    static let shared = StreamingProviderRegistry(providers: [
        YouTubeProvider(),
        DisneyPlusProvider(),
        VideoFileProvider(id: "mp4"), VideoFileProvider(id: "webm"), VideoFileProvider(id: "mkv")
    ])

    private let providers: [StreamingProvider]

    init(providers: [StreamingProvider]) {
        self.providers = providers
    }

    func resolve(_ input: String, startTime: Int? = nil) -> StreamingMedia? {
        // Normalise pasted text once, so providers only ever see a usable URL.
        let input = Self.normalizedInput(input) ?? input
        return providers.compactMap { $0.resolve(input, startTime: startTime) }.first
    }

    /// Turns what people actually paste into a URL: bare hosts without a
    /// scheme, links wrapped in quotes or brackets, percent-encoded links from
    /// share sheets, and links embedded in a sentence.
    static func normalizedInput(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A bare host pasted without a scheme: youtube.com/watch?v=…
        let bareHost = #"^[A-Za-z0-9.-]+\.[A-Za-z]{2,}(:\d+)?([/?#].*)?$"#
        if trimmed.range(of: bareHost, options: .regularExpression) != nil,
           let url = URL(string: "https://" + trimmed) {
            return url.absoluteString
        }

        // A normal URL, possibly wrapped in quotes or angle brackets by chat or email.
        let unwrapped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>()[]{} ,;."))
        if let url = URL(string: unwrapped), url.scheme != nil, url.host != nil {
            return url.absoluteString
        }

        // A percent-encoded share link.
        if let decoded = trimmed.removingPercentEncoding,
           decoded != trimmed,
           let url = URL(string: decoded), url.scheme != nil, url.host != nil {
            return url.absoluteString
        }

        // A link embedded in pasted text ("Watch this: https://youtu.be/…").
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = detector.firstMatch(in: trimmed, options: [], range: range),
               let url = match.url {
                return url.absoluteString
            }
        }

        return nil
    }

    func playbackURL(for mediaID: String, startTime: Int? = nil) -> URL? {
        provider(for: mediaID)?.playbackURL(for: mediaID, startTime: startTime)
    }

    func resolves(_ input: String, to mediaID: String) -> Bool {
        resolve(input)?.mediaID == mediaID
    }

    func thumbnailURL(for mediaID: String) -> URL? {
        provider(for: mediaID)?.thumbnailURL(for: mediaID)
    }

    func providerName(for mediaID: String) -> String {
        provider(for: mediaID)?.displayName ?? "Streaming"
    }

    private func provider(for mediaID: String) -> StreamingProvider? {
        if mediaID.hasPrefix("mkv:") { return providers.first { $0.id == "mkv" } }
        if mediaID.hasPrefix("webm:") { return providers.first { $0.id == "webm" } }
        if mediaID.hasPrefix("mp4:") {
            return providers.first { $0.id == "mp4" }
        }
        if mediaID.hasPrefix("disneyplus:") {
            return providers.first { $0.id == "disneyplus" }
        }
        return providers.first { $0.id == "youtube" }
    }
}
