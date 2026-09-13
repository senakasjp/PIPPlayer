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
        components.path = "/watch"
        var queryItems = [URLQueryItem(name: "v", value: mediaID)]
        if let startTime, startTime > 0 {
            queryItems.append(URLQueryItem(name: "t", value: "\(startTime)"))
        }
        components.queryItems = queryItems
        return components.url
    }

    func thumbnailURL(for mediaID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(mediaID)/mqdefault.jpg")
    }

    private func extractVideoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        let host = url.host?.lowercased() ?? ""

        if host.contains("youtu.be") {
            let last = url.pathComponents.last
            if let last, !last.isEmpty, last != "/" { return last }
            return nil
        }

        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
            // Watch URL: youtube.com/watch?v=VIDEO_ID
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return videoID
            }
            // Embed URL: youtube.com/embed/VIDEO_ID or youtube-nocookie.com/embed/VIDEO_ID
            let parts = url.pathComponents
            if let embedIndex = parts.firstIndex(of: "embed"), embedIndex + 1 < parts.count {
                let id = parts[embedIndex + 1]
                if !id.isEmpty { return id }
            }
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
            playbackURL: playbackURL(for: mediaID, startTime: startTime) ?? url,
            defaultTitle: "Disney+ Video",
            canResumeWithURLParameter: false
        )
    }

    func playbackURL(for mediaID: String, startTime: Int?) -> URL? {
        guard mediaID.hasPrefix("\(id):") else { return nil }
        let path = String(mediaID.dropFirst(id.count + 1))
        return URL(string: "https://www.disneyplus.com\(path)")
    }

    func thumbnailURL(for mediaID: String) -> URL? {
        nil
    }

    private func supports(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "disneyplus.com" || host.hasSuffix(".disneyplus.com")
    }

    private static func mediaID(for url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        return "disneyplus:\(path)"
    }
}

struct StreamingProviderRegistry {
    static let shared = StreamingProviderRegistry(providers: [
        YouTubeProvider(),
        DisneyPlusProvider()
    ])

    private let providers: [StreamingProvider]

    init(providers: [StreamingProvider]) {
        self.providers = providers
    }

    func resolve(_ input: String, startTime: Int? = nil) -> StreamingMedia? {
        providers.compactMap { $0.resolve(input, startTime: startTime) }.first
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
        if mediaID.hasPrefix("disneyplus:") {
            return providers.first { $0.id == "disneyplus" }
        }
        return providers.first { $0.id == "youtube" }
    }
}
