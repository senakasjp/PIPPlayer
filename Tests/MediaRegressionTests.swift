import AppKit
import WebKit

@main
struct MediaRegressionTests {
    @MainActor static func main() {
        let registry = StreamingProviderRegistry.shared
        for input in ["file:///tmp/My%20Movie.mp4", "https://example.com/movie.MP4?token=abc"] {
            guard let media = registry.resolve(input) else { fatalError("MP4 must resolve: \(input)") }
            precondition(media.providerID == "mp4")
            precondition(registry.playbackURL(for: media.mediaID) == media.playbackURL)
            precondition(registry.providerName(for: media.mediaID) == "MP4")
        }
        precondition(registry.resolve("file:///tmp/document.pdf") == nil)
        precondition(registry.resolve("javascript:movie.mp4") == nil)
        precondition(registry.resolve("https://www.youtube.com/watch?v=abc")?.providerID == "youtube")
        for input in ["file:///tmp/My%20Movie.webm", "https://example.com/movie.WEBM?token=abc"] {
            guard let media = registry.resolve(input) else { fatalError("WebM must resolve") }
            precondition(media.providerID == "webm")
            precondition(registry.playbackURL(for: media.mediaID) == media.playbackURL)
            precondition(registry.providerName(for: media.mediaID) == "WebM")
        }
        let receiver = DropReceiverView(frame: .zero)
        precondition(receiver.registeredDraggedTypes.contains(.fileURL), "Finder file drops must be registered")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let youtube = "https://www.youtube.com/watch?v=M7lc1UVf-VE"
        board.setString(youtube, forType: .string)
        precondition(receiver.droppedURLString(from: board) == youtube)
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/My Movie.mp4") as NSURL])
        precondition(receiver.droppedURLString(from: board) == "file:///tmp/My%20Movie.mp4")
        board.clearContents()
        board.setString("not a video", forType: .string)
        precondition(receiver.droppedURLString(from: board) == nil)
        let playlist = registry.resolve("https://www.youtube.com/watch?v=M7lc1UVf-VE&list=PLtest&index=2")
        precondition(playlist?.mediaID == "youtube-playlist:PLtest")
        precondition(playlist?.playbackURL.query?.contains("index=2") == true)
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/Video.webm") as NSURL])
        precondition(receiver.droppedURLString(from: board) == "file:///tmp/Video.webm")
        var received: String?
        precondition(WebView.receiveDrop([NSItemProvider(object: youtube as NSString)]) { received = $0 })
        let deadline = Date().addingTimeInterval(3)
        while received == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(received == youtube, "Asynchronous drops must reach playback on the main run loop")
        print("Media regression checks passed")
    }
}
