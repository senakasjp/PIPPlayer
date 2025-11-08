import Foundation

struct URLHelper {
    static func extractVideoID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmed) else {
            return nil
        }

        let host = url.host?.lowercased() ?? ""

        // youtu.be format
        if host.contains("youtu.be") {
            let videoID = url.pathComponents.last
            return videoID
        }

        // youtube.com format
        if host.contains("youtube.com") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let videoID = queryItems.first(where: { $0.name == "v" })?.value {
                return videoID
            }
        }

        return nil
    }

    static func makeWatchURL(videoID: String) -> String {
        return "https://www.youtube.com/watch?v=\(videoID)"
    }
}
