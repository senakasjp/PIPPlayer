# YouTube Player contributor context

This is a native macOS SwiftUI/AppKit application with WebKit playback, not a React or Firebase project.

## Project map

- `YouTubePlayer/YouTubePlayerApp.swift`: application, menus, settings and watch history.
- `YouTubePlayer/ContentView.swift`: playback coordination, window behavior and WebKit messaging.
- `YouTubePlayer/StreamingProvider.swift`: YouTube, Disney+ and MP4 URL resolution.
- `YouTubePlayer/WebView.swift`: native web view and asynchronous drag/drop delivery.
- `YouTubePlayer/player.html`: official YouTube IFrame API bridge, including playlists.
- `YouTubePlayer/PlayerToolbar.swift`: responsive playback controls.
- `YouTubePlayer/PlaylistView.swift`: persistent queue editor.

Read `README.md` for usage, `design.md` for architecture and UI tokens, and `Tests/README.md` for checks.

## Build and verification

```sh
xcodebuild -project YouTubePlayer.xcodeproj -scheme YouTubePlayer -configuration Release -derivedDataPath /tmp/YouTubePlayerBuild build
```

Run the regression checks documented in `Tests/README.md`. For UI changes, exercise the actual native app and inspect compact/wide controls plus populated/empty playlists. Web browser audits do not verify native SwiftUI layout. Report unverified behavior explicitly.

## Implementation constraints

- Preserve unrelated work and generated build artifacts already present in the workspace.
- Keep provider resolution centralized; YouTube playback uses the documented IFrame API.
- Keep drop feedback mounted and defer accepted-drop delivery; do not mutate window layout synchronously within native drag callbacks.
- Preserve toolbar access to volume and queue navigation at compact widths.
- Use native semantic controls, accessibility labels and the documented design tokens.
- Do not alter secrets, signing credentials, or Git internals. Do not publish, push or send external messages without user authorization.

## Current verification limits

The reported drag crash was not reproduced during the September 16, 2026 checks. Drop handling was hardened, MP4 playback and queue advancement were exercised, and the Release build plus regression checks passed. Modern UI captures passed visual review; full VoiceOver operation and measured contrast were not audited.
