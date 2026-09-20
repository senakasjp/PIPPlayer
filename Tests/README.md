# Regression checks (macOS)

Run from the repository root in a normal macOS terminal (pasteboard access is required):

```sh
work=$(mktemp -d)
swiftc -module-cache-path "$work/modules" YouTubePlayer/StreamingProvider.swift YouTubePlayer/WebView.swift Tests/MediaRegressionTests.swift -o "$work/media-tests"
"$work/media-tests"
node Tests/PlaylistBridgeTests.cjs
rm -rf "$work"
```

The Swift checks cover MP4/WebM resolution, file/text pasteboards, unsupported drops, asynchronous item-provider delivery, and playlist URL/index preservation. The JavaScript checks cover queued YouTube playlist loading, cueing, navigation, and final-item completion.

## Release build

Run all bridge, hover, and source-error checks with `node --test Tests/*Tests.cjs`.
The native Swift checks require macOS on Apple Silicon with Xcode installed at
`/Applications/Xcode.app`. Source error checks cover failures before metadata,
redirected-source identity, preserved resume positions, canceled or superseded
navigation, and WebKit media handoffs.

```sh
xcodebuild -project YouTubePlayer.xcodeproj -scheme YouTubePlayer -configuration Release -derivedDataPath /tmp/YouTubePlayerBuild build
```

## Manual native checks

- Drop a YouTube URL as text and as a browser link. Confirm playback loads and the app stays responsive; repeat with Hover Transparency enabled.
- Drop local MP4 and WebM files, open direct MP4 and WebM URLs, and try an unsupported file. Confirm supported playback and safe rejection of unsupported input.
- Open Playlist with ⌘⇧P. Add links and multiple MP4/WebM files, reorder entries, play a selected entry, and confirm automatic advancement and persistence after relaunch.
- Open a YouTube playlist URL containing `list=` and check previous/next navigation.
- Inspect toolbar widths of 280, 360, 600, 700 and 900 points. Play/pause, seeking and playlist access must remain available; narrow layouts expose volume and queue navigation through Playback options.
- Inspect playlist empty, populated and invalid-input states. Check keyboard focus and named accessibility controls.
- Disable Hover Transparency with ⌘T when testing on-window controls; restore the original preference afterward.

## Recorded results: September 16, 2026

Release build, Swift media/drop regressions and JavaScript playlist bridge regressions passed. Native MP4 playback, completion signaling and queue advancement were exercised. The modern styling pass inspected actual SwiftUI toolbar previews at 300 and 700 points and populated/empty playlist states; visual and source-integrity reviewers passed the supplied toolbar and populated playlist captures.

Evidence is saved under `build/UpdatedPlayer/verification/` with the packaged app. Earlier toolbar sizing checks predate the modern styling pass. Automated bridge tests do not establish live online YouTube playlist availability. The original reported drag crash was not reproduced; full VoiceOver operation and measured contrast were not audited.

WebM regression coverage includes local and uppercase remote extensions with query parameters, provider naming, source URL round trips and file pasteboard decoding. A generated VP9 WebM was additionally exercised in native WebKit with the actual injected progress script, verifying playback, viewport geometry and completion events.

Non-YouTube zoom checks: native WebM playback at 150% produced the expected scaled geometry, black video/body backgrounds and a completion event. The live options slider incremented from 100% to 105%; Reset returned it to 100%. Inspect zoom options at compact and wide sizes, and confirm YouTube does not expose this control.

## Direct MKV playback

Run `sh Scripts/setup-vlckit.sh` before building. The MKV regression uses the real bundled decoder and a native video window. Supply a valid 5–10 second MKV containing video and audio:

```sh
sh Scripts/test-mkv-playback.sh /absolute/path/to/short-test.mkv
```

It checks decoding, original source identity, resume, pause, seek, zoom geometry, exactly one completion event, stop cleanup, and invalid-file failure. Media/drop checks also cover MKV URLs, uppercase extensions, query strings, source round trips and file pasteboards.

For a local ad-hoc signed Release build, add `ENABLE_HARDENED_RUNTIME=NO` to the build command. A distributed hardened build must sign the app and embedded framework with the same developer identity; ad-hoc signatures do not satisfy library validation.

Native manual checks: add an MKV through Add Files, play it, pause and seek, change volume, zoom and reset, advance to another item, reopen from history, and switch between MKV and WebKit playback. Confirm no conversion step or external application is involved.

For source-read recovery, use disposable corrupt MP4 and MKV files. Confirm the
error alert names the source and offers Retry/Cancel, including with Hover
Transparency enabled. Replace the corrupt fixture with valid media and retry;
confirm playback recovers. Test an unavailable file or disconnected drive and
confirm the playlist does not advance. Cancel must dismiss the alert without
clearing the saved position. The MKV suite also checks corrupt-file failure,
absence of a completion event, and recovery with a valid fixture.
