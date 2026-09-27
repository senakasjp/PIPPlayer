import Foundation

@main
struct PlaylistLibraryTests {
    static func main() throws {
        let a = PlaylistNode.item("https://example.com/a.mp4")
        let b = PlaylistNode.item("https://example.com/b.webm")
        let c = PlaylistNode.item("https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "Song")
        let inner = PlaylistNode.folder("Inner", [b])
        let outer = PlaylistNode.folder("Outer", [inner, c])
        var library = [a, outer]

        precondition(library.items.map(\.id) == [a.id, b.id, c.id], "tree order")
        precondition(library.folderCount == 2)
        precondition(library.location(of: b.id)! == (inner.id, 0))
        precondition(library.contains(b.id, within: outer.id) && !library.contains(a.id, within: outer.id))

        library.insert([library.remove(a.id)!], into: inner.id, at: 0)
        precondition(library.node(inner.id)!.children!.map(\.id) == [a.id, b.id], "move into folder")
        library.removeItems { $0.url == b.url }
        precondition(library.items.map(\.id) == [a.id, c.id], "recursive removal keeps folders")

        // Each folder containing the played item remembers it; finishing clears it.
        library.markPlayed(a.id)
        precondition(library.node(outer.id)!.lastPlayedID == a.id && library.node(inner.id)!.lastPlayedID == a.id, "resume points")
        library.clearPlayed(a.id)
        precondition(library.node(outer.id)!.lastPlayedID == nil && library.node(inner.id)!.lastPlayedID == nil, "cleared resume")
        library.markPlayed(c.id)
        precondition(library.node(outer.id)!.lastPlayedID == c.id && library.node(inner.id)!.lastPlayedID == nil)

        // A loading video maps back to its playlist item, preferring the remembered one among duplicates.
        let duplicate = PlaylistNode.item(c.url!)
        var withDuplicate = library + [duplicate]
        let mediaID = c.media!.mediaID
        precondition(withDuplicate.item(playing: mediaID, preferring: nil)?.id == c.id, "first match")
        precondition(withDuplicate.item(playing: mediaID, preferring: duplicate.id)?.id == duplicate.id, "preferred match")
        precondition(withDuplicate.item(playing: "youtube:none", preferring: nil) == nil, "no match")
        withDuplicate.removeAll()

        // Saved library round-trips; a legacy flat queue migrates.
        let decoded = try JSONDecoder().decode([PlaylistNode].self, from: JSONEncoder().encode(library))
        precondition(decoded == library)

        let base = URL(fileURLWithPath: "/tmp/videos")
        let m3u = PlaylistLibrary.m3u(library.items) + "clip.mkv\n#comment\nnot a video\n"
        let parsed = PlaylistLibrary.parseM3U(m3u, relativeTo: base)
        precondition(parsed.map(\.url) == [a.url, c.url, base.appendingPathComponent("clip.mkv").absoluteString], "m3u parse")
        precondition(parsed[1].title == "Song", "m3u titles")
        print("Playlist library checks passed: tree order, moves, removal, persistence, M3U, resume points")
    }
}
