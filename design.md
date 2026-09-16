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
- `MP4Provider`: resolves local files and direct HTTP(S) `.mp4` URLs using the full URL as media identity.
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

## MP4 and Playlists

MP4 URLs use the `MP4Provider`, with `mp4:` plus the complete URL as their identity. Local files load through WebKit's file API. YouTube playlists retain the `list` and `index` parameters and use the official IFrame playlist API.

The native Playlist sheet uses system fonts and controls, semantic secondary/error colors, 24-point outer spacing and 12-point row insets. Its minimum size is 560 × 420 points. Users can add links or MP4 files, reorder, remove, clear, and play entries. The queue persists locally and advances on media completion. Drop feedback remains mounted and changes opacity, avoiding structural layout changes during dragging.

## Responsive Player Toolbar

Preserve the native macOS black video canvas and translucent overlay. The viewing persona needs reliable playback in a small floating window; keyboard and VoiceOver users need named controls at every size.

- Material: dark ultra-thin system material over a 70% black tint, white foreground, secondary text at 75%, 10% white rim, 16% separators, black 25% shadow with 12-point radius and 4-point vertical offset.
- Geometry tokens: 12-point horizontal toolbar padding and 16-point corner radius, 8-point control gap, 4-point tight gap, 32-point button targets, 56-point bar height, 18-point separators, 1-point rim. SF Symbols use 13-point semibold; time uses 11-point monospaced digits.
- `PlayerToolbar` is the reusable primitive: play/pause, flexible seek, playlist, volume. At widths under 360 points, time labels move into the volume/options popover. At 360–599 points elapsed time appears. At 600 points and above, previous/next, both times, and a 96-point volume slider fit inline. Narrow layouts retain volume and previous/next inside the options popover. No minimum bar width forces the window larger.
- Targets remain 32 points instead of shrinking icons to fit. Buttons retain native focus, pressed, and keyboard behavior; all symbols have accessibility labels and help. Seek exposes elapsed and total time. Duration unavailable disables seeking, and invalid numeric progress is clamped safely.
- Native popovers expose volume and queue navigation with 16-point padding, 12-point section gap and 220-point content width. No decorative motion is added; system interactions honor macOS preferences.
- Verify the primitive at 280, 360, 600 and 900 points, including long durations and unavailable media. Web Lighthouse tooling is inapplicable to this native SwiftUI component.

## Modern native polish

The toolbar uses a 56-point dark floating surface, 16-point corners, 70% black tint and a restrained 10% white edge. A 32-point white circular play/pause button is the primary action; secondary controls remain white symbols. Preserve the existing responsive breakpoints and native keyboard focus. Playlist uses a 24-point inset, 24-point semibold heading, 12-point supporting copy, 12-point row inset, 8-point row corners and a subtle accent tint for the playing row. A 40-point SF Symbol anchors the empty state; input and footer are separated from the queue by native dividers. System colors adapt to light/dark appearance. No decorative animation, new dependency or artwork is needed.

## Verification and playback boundaries

The September 16, 2026 Release build and regression checks passed. Native MP4 playback, completion events and queue advancement were exercised. Modern toolbar previews at 300 and 700 points, plus populated and empty playlist states, were inspected; independent visual and source-integrity review passed for the toolbar and populated playlist. Full VoiceOver interaction and measured contrast remain unverified.

MP4 uses a main-frame progress bridge installed at document end. WebKit's standalone media-document audio classes are removed for MP4 so custom controls do not leave the video at audio-control height. YouTube playback remains on the IFrame API. Drag feedback stays mounted, accepted drops deliver asynchronously, and hover transparency is suppressed during active dragging. The original crash was not reproduced during verification.
