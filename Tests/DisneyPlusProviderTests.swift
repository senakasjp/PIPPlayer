import Foundation

@main
struct DisneyPlusProviderTests {
    static func main() {
        let registry = StreamingProviderRegistry.shared
        for input in [
            "https://www.disneyplus.com/",
            "https://www.disneyplus.com/en-nz/browse/entity/example?source=share#details",
            "https://www.disneyplus.com/video/example",
            "https://disneyplus.com/play/example"
        ] {
            guard let media = registry.resolve(input, startTime: 120) else {
                fatalError("Disney+ URL must resolve")
            }
            precondition(media.providerID == "disneyplus")
            precondition(media.playbackURL.absoluteString == input, "Preserve shared URLs")
            precondition(!media.canResumeWithURLParameter)
            precondition(registry.providerName(for: media.mediaID) == "Disney+")
            guard let restored = registry.playbackURL(for: media.mediaID) else {
                fatalError("Saved Disney+ identity must reopen")
            }
            precondition(registry.resolve(restored.absoluteString)?.mediaID == media.mediaID)
        }
        for input in [
            "file://www.disneyplus.com/video/example",
            "ftp://www.disneyplus.com/video/example",
            "https://disneyplus.com.example.org/video/example",
            "https://notdisneyplus.com/video/example",
            "https://user:password@www.disneyplus.com/video/example"
        ] {
            precondition(registry.resolve(input) == nil)
        }
        precondition(registry.playbackURL(for: "disneyplus:invalid") == nil)
        print("Disney+ provider checks passed")
    }
}
