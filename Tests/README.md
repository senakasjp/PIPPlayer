# Regression checks (macOS)

Run from the repository root in a normal macOS terminal (pasteboard access is required):

```sh
work=$(mktemp -d)
swiftc -module-cache-path "$work/modules" YouTubePlayer/StreamingProvider.swift YouTubePlayer/WebView.swift Tests/MediaRegressionTests.swift -o "$work/media-tests"
"$work/media-tests"
node Tests/PlaylistBridgeTests.cjs
rm -rf "$work"
```

The Swift checks cover MP4 resolution, file/text pasteboards, unsupported drops, asynchronous item-provider delivery, and playlist URL/index preservation. The JavaScript checks cover queued YouTube playlist loading, cueing, navigation, and final-item completion.

## Release build

```sh
xcodebuild -project YouTubePlayer.xcodeproj -scheme YouTubePlayer -configuration Release -derivedDataPath /tmp/YouTubePlayerBuild build
```

## Manual native checks

- Drop a YouTube URL as text and as a browser link. Confirm playback loads and the app stays responsive; repeat with Hover Transparency enabled.
- Drop a local MP4, open a direct MP4 URL, and try an unsupported file. Confirm supported playback and safe rejection of unsupported input.
- Open Playlist with ⌘⇧P. Add links and multiple MP4 files, reorder entries, play a selected entry, and confirm automatic advancement and persistence after relaunch.
- Open a YouTube playlist URL containing `list=` and check previous/next navigation.
- Inspect toolbar widths of 280, 360, 600 and 900 points. Play/pause, seeking and playlist access must remain available; narrow layouts expose volume and queue navigation through Playback options.
- Inspect playlist empty, populated and invalid-input states. Check keyboard focus and named accessibility controls.
- Disable Hover Transparency with ⌘T when testing on-window controls; restore the original preference afterward.

## Recorded results: September 16, 2026

Release build, Swift media/drop regressions and JavaScript playlist bridge regressions passed. Native MP4 playback, completion signaling and queue advancement were exercised. The modern styling pass inspected actual SwiftUI toolbar previews at 300 and 700 points and populated/empty playlist states; visual and source-integrity reviewers passed the supplied toolbar and populated playlist captures.

Evidence is saved under `build/UpdatedPlayer/verification/` with the packaged app. Earlier toolbar sizing checks predate the modern styling pass. Automated bridge tests do not establish live online YouTube playlist availability. The original reported drag crash was not reproduced; full VoiceOver operation and measured contrast were not audited.
