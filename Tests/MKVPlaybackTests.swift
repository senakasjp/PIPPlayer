import AppKit
import Combine

@main
struct MKVPlaybackTests {
    @MainActor static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(condition(), "Timed out")
    }

    @MainActor static func main() throws {
        precondition(CommandLine.arguments.count == 2, "Pass a short MKV fixture path")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.finishLaunching()
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let media = StreamingProviderRegistry.shared.resolve(input.absoluteString) else {
            fatalError("MKV must resolve")
        }
        let playback = MKVPlayback()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = playback.surface
        window.orderFront(nil)
        playback.play(media, startTime: 1, volume: 30)
        waitUntil { playback.snapshot?.state == 1 && (playback.snapshot?.time ?? 0) >= 1 }
        precondition(playback.snapshot?.mediaID == media.mediaID)
        precondition((playback.snapshot?.duration ?? 0) > 0)
        playback.togglePlayPause()
        waitUntil { playback.snapshot?.state == 2 }
        playback.surface.zoom = 1.5
        playback.surface.layoutSubtreeIfNeeded()
        precondition(playback.surface.videoView.frame.width == 960)
        playback.seek(to: 2)
        playback.togglePlayPause()
        waitUntil { (playback.snapshot?.time ?? 0) >= 2 }
        var completions = 0
        let observation = playback.updates.sink { if $0.state == 0 { completions += 1 } }
        waitUntil { playback.snapshot?.state == 0 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        precondition(completions == 1, "Queue completion must fire once")
        observation.cancel()
        let previousSession = playback.sessionID
        playback.togglePlayPause()
        waitUntil { playback.snapshot?.state == 1 }
        precondition(playback.sessionID != previousSession, "Replay must start a fresh session")
        playback.play(media, startTime: 0, volume: 0)
        playback.stop()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        precondition(playback.snapshot == nil, "Stopped playback must not publish stale progress")
        guard let bad = StreamingProviderRegistry.shared.resolve("file:///tmp/missing-mkv-regression.mkv") else {
            fatalError("Missing MKV must resolve before loading")
        }
        playback.play(bad, startTime: 0, volume: 0)
        waitUntil { playback.snapshot?.state == -1 }
        playback.stop()
        print("Direct MKV decoding, resume, pause, seek, zoom, completion, stop and failure checks passed")
    }
}
