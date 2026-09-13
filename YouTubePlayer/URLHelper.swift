import Foundation

struct URLHelper {
    static func extractVideoID(from urlString: String) -> String? {
        StreamingProviderRegistry.shared.resolve(urlString)?.mediaID
    }

    static func makeWatchURL(videoID: String, startTime: Int? = nil) -> String {
        StreamingProviderRegistry.shared.playbackURL(for: videoID, startTime: startTime)?.absoluteString
            ?? "https://www.youtube.com/watch?v=\(videoID)"
    }
}
