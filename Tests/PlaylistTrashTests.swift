import Foundation

@main
struct PlaylistTrashTests {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("playlist-trash-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = folder.appendingPathComponent("disposable-test.webm")
        try Data("Disposable test fixture, not user media".utf8).write(to: fixture)
        try PlaylistView.trashOriginalFile(at: fixture)
        precondition(!FileManager.default.fileExists(atPath: fixture.path))
        let remote = URL(string: "https://example.com/video.webm")!
        do {
            try PlaylistView.trashOriginalFile(at: remote)
            fatalError("Remote URL must be rejected")
        } catch {}
        let directory = folder.appendingPathComponent("directory.webm")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try PlaylistView.trashOriginalFile(at: directory)
            fatalError("Directories must be rejected")
        } catch {}
        precondition(FileManager.default.fileExists(atPath: directory.path))
        do {
            try PlaylistView.trashOriginalFile(at: fixture)
            fatalError("Missing file must fail")
        } catch {}
        print("Trash checks passed: local file moved, remote URL/directory/missing file rejected")
    }
}
