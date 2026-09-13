# Streaming Provider Design

## Goal

Extend the macOS player beyond YouTube while keeping provider-specific behavior isolated, portable, and easy to expand.

## Pattern

The app uses the Strategy pattern through `StreamingProvider`.

Each streaming service implements the same interface:

```swift
protocol StreamingProvider {
    var id: String { get }
    var displayName: String { get }

    func resolve(_ input: String, startTime: Int?) -> StreamingMedia?
    func playbackURL(for mediaID: String, startTime: Int?) -> URL?
    func thumbnailURL(for mediaID: String) -> URL?
}
```

`StreamingProviderRegistry` owns the list of strategies and is the only place that selects a provider. The UI asks the registry to resolve an input URL and then loads the returned `StreamingMedia` in `WKWebView`.

## Current Providers

- `YouTubeProvider`: supports `youtube.com/watch?v=...` and `youtu.be/...`, creates resume URLs using the `t=` query parameter, and provides YouTube thumbnails.
- `DisneyPlusProvider`: supports `disneyplus.com` and subdomains, loads the original Disney+ URL, and stores a stable media ID from the Disney+ path.

## Flow

1. User opens, pastes, or drops a URL.
2. `ContentView` calls `StreamingProviderRegistry.resolve(...)`.
3. The matching provider returns `StreamingMedia` with `mediaID`, `playbackURL`, display name, and resume capability.
4. `ContentView` loads `playbackURL` into the shared `WKWebView`.
5. The injected progress script detects the active provider from `window.location.hostname` and posts progress with the provider-specific `mediaID`.
6. `AppSettings` records history using the `mediaID` and stores `sourceURL` so non-YouTube entries can be reopened exactly.

## Web Session Robustness

- The player uses `WKWebsiteDataStore.default()` so cookies, local storage, and login sessions persist across app launches.
- JavaScript is explicitly enabled, and JavaScript-created windows are allowed.
- Login links that request a new browser window or popup are loaded back into the same player web view instead of being dropped.
- JavaScript alert and confirm panels are bridged to native `NSAlert` dialogs so provider login flows can complete when they require confirmation.

## Extending

To add another service:

1. Add a new type that conforms to `StreamingProvider`.
2. Implement URL recognition in `resolve`.
3. Return a stable `mediaID` that will not collide with other providers. Prefix non-YouTube IDs with the provider ID, for example `netflix:/watch/...`.
4. Implement `playbackURL(for:startTime:)`. Return the original content URL if the service does not support URL-based resume.
5. Optionally implement `thumbnailURL(for:)`.
6. Register the provider in `StreamingProviderRegistry.shared`.
7. Extend the progress script in `ContentView` if the provider needs custom media ID extraction from the loaded page.

## Portability Notes

- The core player remains `WKWebView` based, so each provider is loaded as its normal web app rather than through private APIs.
- Provider-specific parsing is kept out of the SwiftUI views except for web progress extraction.
- Existing YouTube history IDs are preserved as raw YouTube video IDs for compatibility with persisted data.
- Non-YouTube providers use prefixed IDs to avoid collisions.

## Limits

- Disney+ playback depends on what Disney+ allows inside macOS `WKWebView`, including authentication, DRM, and regional availability.
- Disney+ resume is tracked locally when the page exposes a standard HTML `video` element, but Disney+ does not currently receive a URL start-time parameter.
- If Disney+ requires browser capabilities or DRM paths that WebKit does not expose to third-party apps, the app can preserve login state but still may not be able to play protected video.
