# YouTube Player

A native macOS mini-player for YouTube videos and playlists, local and linked MP4/WebM files, and supported streaming pages. Includes a responsive floating toolbar, saved playback queues, menu bar controls, and watch history.

## YouTube API ToS / Developer Policy Compliance

For YouTube, this app renders video through YouTube's official **IFrame Player API**
(`YT.Player`), loaded from the bundled local `YouTubePlayer/player.html`. Everything
else (window chrome, the native control bar, history) is native SwiftUI. To stay
compliant with the YouTube API Terms of Service and Developer Policies, contributors
must preserve these invariants:

- **The player is rendered exactly as YouTube serves it.** No ad blocking, ad
  skipping, or ad detection of any kind. There is intentionally no `ad-showing`
  inspection or `.ytp-*` overlay CSS — these were removed.
- **No stripping or hiding of YouTube's UI/branding.** The injected CSS resets only
  scrollbars and body margins; it must not touch any YouTube player controls,
  overlays, end screens, or attribution.
- **No downloading, caching, or re-hosting** of video/audio streams. Playback is
  never read from a `<video>` element for YouTube; position/state come from the
  documented IFrame API methods over the JS bridge.
- **Natural referrer.** `player.html` is loaded via `loadHTMLString(baseURL:
  https://www.youtube.com)` so the IFrame API's postMessage origin check passes and
  WKWebView sends its normal `strict-origin-when-cross-origin` referrer. Do not use
  `noreferrer` or the `nocookie` host, and do not nest the YouTube iframe.
- **No autoplay before the player is mounted.** The first-launch demo video is
  *cued*, not auto-played, until the user presses play.

The JS↔Swift bridge uses a single `playerBridge` message channel and only documented
IFrame methods: `loadVideoById`/`cueVideoById`, `playVideo`, `pauseVideo`, `seekTo`,
`setVolume`, `loadPlaylist`/`cuePlaylist`, `nextVideo`/`previousVideo`, plus `onReady`/`onStateChange`/`onError`. MP4 and WebM use native HTML video events through the WebKit bridge.

## Features

### Playback
- **Open YouTube URLs**: Paste, drop, or enter a YouTube link to start playback or replace the current video
- **Last Video Restore**: Remembers the last opened video and restores it on launch
- **Resume Playback Position**: Stores timeline progress per video permanently and resumes from the saved time however the video is opened (URL, history, queue or launch). Moved local files are matched by file name; videos played to the end start over.
- **Responsive Toolbar**: A dark floating SwiftUI toolbar with a prominent circular play/pause button, seeking, volume, and playlist access. Compact windows move secondary controls into Playback options.
- **Minimal Viewing UI**: Hides only scrollbars; the YouTube player itself is shown unmodified

### Video Files and Playlists
- **MKV playback**: Open local `.mkv` files or direct HTTP(S) MKV URLs using the bundled VLC decoder. Supports the existing playback controls, history and playlists.
- **MP4/WebM playback**: Drop a local `.mp4` or `.webm` file or open a direct HTTP(S) video URL. Codec support depends on macOS WebKit.
- **YouTube playlists**: Open a URL containing `list=`; playlist position is preserved and previous/next controls navigate its entries.
- **Saved queue**: Open **Player → Playlist…** with **⌘⇧P**, add links or multiple MP4/WebM files, reorder or remove entries, and play an item. The queue persists locally and advances when playback ends.
- **Drop handling**: Supports URL, text, and file drops; unsupported inputs are rejected. Delivery is deferred to avoid changing layout during the native drop callback.

### Library and History
- **Recent Videos**: Tracks recently opened videos in the menu bar
- **Watch History**: Keeps a larger persistent history list with thumbnails and resume times
- **Remove Watched Items**: Delete individual watched entries from the watch history/library
- **Notes**: Add free-form notes to each watched video
- **Star Ratings**: Mark priority with 1-5 stars
- **Thumbs Down**: Mark videos you do not want to revisit
- **Update In Place**: Reopening an existing video updates the same history entry instead of creating a duplicate
- **Preserve Metadata**: Notes, ratings, thumbs-down, and timeline stay attached to the same video entry

### Window and Menu Bar Behavior
- **Menu Bar Control**: Quick access to player features through a persistent status item
- **Floating Window**: Always stays on top of other applications (toggleable)
- **Hover Transparency**: Window becomes transparent and click-through on hover
- **80% Transparency Preset**: One-tap 80% opacity that stays clickable (⌘8)
- **Opacity Dimmer**: Toggle to 25% opacity while keeping clicks active (⌘P)
- **Fill Player Window**: Crops the video to cover the whole window (no letterboxing), using the video's *real* aspect ratio fetched from YouTube's oEmbed endpoint — not a hardcoded 16:9 guess, so Shorts (9:16) and other non-standard uploads crop correctly too. On by default.
- **16:9 Resize Lock**: Locks the window itself to a 16:9 shape while resizing. On by default; enforced pre-paint (no flicker). Independent of Fill Player Window — the window can be any shape and the video still fills correctly.
- **Close Window Without Quitting**: Closing the player window stops audio and closes the window, but keeps the menu bar app running until you quit explicitly

### Controls

#### Menu Bar Icon
Click the play button icon in the menu bar to access:
- **Open URL...** (⌘O) - Open a supported video or playlist URL
- **Hover Transparency** (⌘T) - Enable/disable hover transparency mode
- **Always On Top** (⌘L) - Control whether window floats above others
- **80% Transparency** (⌘8) - Set a fixed 80% transparent, still-clickable window
- **Toggle Opacity** (⌘P) - Dim to 25% opacity (clickable) or restore to 100%
- **Fill Player Window** (⌘⇧F) - Expand the player area
- **Lock 16:9 While Resizing** - Keep the player ratio stable while resizing
- **Recent Videos** - Reopen tracked items from the menu bar
- **Quit** (⌘Q) - Close the application

## Design Architecture

### Application Structure

```
YouTubePlayer/
├── YouTubePlayerApp.swift      # Main app entry point & menu bar setup
├── ContentView.swift            # Main UI and window management
├── WebView.swift                # WKWebView wrapper for SwiftUI
├── PlayerToolbar.swift          # Responsive native playback controls
├── PlaylistView.swift           # Saved queue editor
├── StreamingProvider.swift      # Provider selection and URL resolution
├── player.html                 # YouTube IFrame API bridge
├── URLHelper.swift              # YouTube URL parsing utilities
└── Info.plist                   # App configuration
```

### Key Components

#### 1. App Delegate (YouTubePlayerApp.swift)
- **Menu Bar Icon**: Creates a persistent status item in the macOS menu bar
- **Menu Management**: Provides quick access to all app features
- **Recent Video Menu**: Rebuilds the menu from persisted history
- **Notification System**: Uses NotificationCenter to communicate with ContentView

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    // Creates menu bar icon with play.rectangle.fill symbol
    // Manages menu items and keyboard shortcuts
}
```

#### 2. Content View (ContentView.swift)
- **IFrame Player API**: Loads the bundled `player.html` and drives YouTube playback through the `YT.Player` JS bridge (`ytLoad`/`ytPlay`/`ytPause`/`ytSeek`/`ytSetVolume`); never loads the `youtube.com/watch` page directly
- **Native Control Bar**: Renders the play/pause/scrub/volume strip and syncs it from `onStateChange`/timer events posted over `playerBridge`
- **State Management**: Tracks transparency mode, hover state, active playback, and window level
- **Window Configuration**: Sets up transparent titlebar and floating behavior
- **Playback Restore**: Reloads the last saved video and playback position (via the IFrame API for YouTube)
- **Progress Persistence**: Saves timeline progress back into app state and user defaults
- **Hover Detection**: Uses `.onHover` modifier to detect mouse position
- **Window Manipulation**: Controls alpha value and mouse event pass-through

> Non-YouTube providers (e.g. Disney+) still load their page directly into the
> WKWebView and report progress via the `videoProgress` handler; the IFrame path
> applies to YouTube only.

```swift
@State private var isTransparent = true   // Hover mode on/off
@State private var isAlwaysOnTop = true   // Floating window on/off
@State private var isHovering = false     // Current hover state
```

#### 3. WebView Wrapper (WebView.swift)
- SwiftUI wrapper around WKWebView
- Enables YouTube video playback in native macOS window

#### 4. URL Helper (URLHelper.swift)
- Extracts video IDs from various YouTube URL formats
- Converts to clean watch URLs for playback

### Transparency & Hover Behavior

The app implements a sophisticated hover-based transparency system:

#### Default Mode (Transparency Enabled)
1. **Not Hovering**: Window is opaque (alpha = 1.0), clickable
2. **Hovering**: Window becomes transparent (alpha = 0.1), click-through enabled
3. **Mouse Exits**: Returns to opaque and clickable

#### Disabled Mode (Transparency Off)
- Window always remains opaque and clickable
- Hover events are ignored

```swift
func handleHoverChange(_ hovering: Bool) {
    guard isTransparent else { return }
        if hovering {
            window.alphaValue = 0.1          // 90% transparent
            window.ignoresMouseEvents = true  // Click-through
        } else {
            window.alphaValue = 1.0          // Opaque
            window.ignoresMouseEvents = false // Clickable
        }
}
```

### Window Configuration

```swift
window.titlebarAppearsTransparent = true  // Seamless title bar
window.styleMask.insert(.fullSizeContentView)  // Full window content
window.isOpaque = false                   // Allow transparency
window.backgroundColor = .black           // Black background
window.level = .floating                  // Always on top
window.collectionBehavior.insert(.canJoinAllSpaces)    // Follow space changes
window.collectionBehavior.insert(.fullScreenAuxiliary) // Visible with fullscreen apps
```

### Fill Player Window (video overflow/crop)

Implemented in `player.html`, not Swift — the IFrame API iframe is sized/positioned in JS, not left at a flat `width/height: 100%`:

1. `window.ytLoad(id, ...)` fires `fetchContentAspectRatio(id)`, which calls YouTube's no-auth oEmbed endpoint (`https://www.youtube.com/oembed?format=json&url=...`) and reads the real `width`/`height` for that specific video. Same-origin from the page's `baseURL` (`https://example.com`) is not required — the endpoint echoes back whatever `Origin` header it receives, so it works cross-origin too.
2. `layoutPlayerFrame()` sizes the iframe larger than the window on whichever axis is needed to cover it at that aspect ratio, centers it with `position: absolute`, and relies on `body { overflow: hidden }` to clip the excess.
3. Falls back to a 16:9 assumption if the oEmbed fetch fails or hasn't resolved yet, and re-runs on `onReady` and on every `resize` event.

**Why oEmbed and not a hardcoded 16:9:** the naive version (fixed 16:9) forces an extreme, wrong-looking zoom whenever the actual content isn't 16:9 — most visibly on YouTube Shorts (9:16) or when the *window* itself isn't 16:9-shaped. Fetching the actual ratio per-video fixes both cases with the same code path.

**This is independent of the window's own shape/aspect ratio** — the crop math re-derives from whatever `window.innerWidth/innerHeight` currently are, so it doesn't matter whether the 16:9 window lock (below) is on, off, or the window is a completely different shape (e.g. an external tiling window manager resized it).

### 16:9 Window Lock

Implemented in `PlayerWindowCoordinator` (`ContentView.swift`), as an `NSWindowDelegate`:

- `windowWillResize(_:to:)` — the primary path. Returns a 16:9-corrected size to AppKit *before* anything is committed or painted, so interactive drag-resizing only ever renders the final, correct frame — no flicker.
- `windowDidResize(_:)` → `applyLockedAspectRatio(to:)` — a backstop for resizes that bypass the `windowWillResize` negotiation entirely (observed with `setFrame` calls issued by another process, e.g. an external window manager). Applied synchronously, not deferred to the next run-loop turn, to minimize the race window against anything else trying to re-assert a different frame right after. It's a no-op when `windowWillResize` already produced the correct size (epsilon-guarded), so the common interactive-resize path never double-paints.

`AppSettings.lockAspectRatio16x9Enabled` and `.fillPlayerWindowEnabled` are both hard-defaulted `true` in code, and `loadPersistedValues()` deliberately skips restoring either from `UserDefaults`. **Do not "fix" this by making them restore from defaults again** — that was tried and is exactly what broke the 16:9 lock previously: a stale `false` persisted from an earlier session/build silently overrode the in-code default on every launch, so the feature looked "randomly" disabled with no code-level indication why. If you need a real user-facing off switch for either, the toggle already exists (menu items "Fill Player Window" / "Lock 16:9 While Resizing"); just don't let `loadPersistedValues()` restore a stored value for them.

### External Tiling Window Managers (AeroSpace, yabai, etc.)

Three separate, sometimes-conflicting concerns come up under a tiling WM:

1. **Resizing/tiling at all.** `.canJoinAllSpaces` (used for "follow across Spaces", above) is exactly the collection-behavior flag most tiling WMs read as "this window is floating/sticky — leave it alone." With it set, AeroSpace won't pull the window into its tiling grid. This is a real trade-off, not a bug: drop `.canJoinAllSpaces` if you want AeroSpace to tile/resize it, keep it if you want cross-Space follow. You can't cleanly have AeroSpace-tiling *and* native macOS all-spaces-follow on the same window at once.
2. **Fighting the 16:9 lock.** If `lockAspectRatio16x9Enabled` is on, `windowWillResize` will correct *any* resize — including one an external WM just requested — back to 16:9. If you want AeroSpace to freely size the window, turn the 16:9 lock off (menu item, or flip the code default — see the warning above about not restoring it from `UserDefaults` if you do).
3. **Following you across AeroSpace *workspaces* specifically.** This is different from #1's macOS *Spaces*. AeroSpace has no native sticky/all-workspaces window feature at all — see [nikitabobko/AeroSpace#2](https://github.com/nikitabobko/AeroSpace/issues/2), open since 2024, with no built-in flag or config option that fixes it. The only known workaround (used by other AeroSpace users in that thread) is scripting `exec-on-workspace-change` to actively move the window to whatever workspace becomes focused. That's configured in `~/.config/aerospace/aerospace.toml` (outside this repo), not in this app:

    ```toml
    exec-on-workspace-change = ['/bin/bash', '-c',
        'WIN=$(aerospace list-windows --monitor all --app-bundle-id com.example.YouTubePlayer --format "%{window-id}" 2>/dev/null); [ -n "$WIN" ] && aerospace move-node-to-workspace --window-id "$WIN" "$AEROSPACE_FOCUSED_WORKSPACE"'
    ]
    ```

    Verified working by switching workspaces via `aerospace workspace <name>` and confirming with `aerospace list-windows --monitor all --app-bundle-id com.example.YouTubePlayer --format "%{workspace}"`. Known limitation (from the same upstream thread): this moves the window but doesn't force focus, so it can end up behind whatever's already focused on the workspace you land on — not brought fully to front automatically.

### CSS Customization

The app injects only a minimal reset so the player surface sits flush. It does
**not** hide or alter any YouTube player UI, overlays, or branding (see the
compliance section above):

```css
::-webkit-scrollbar { display: none !important; }
html, body { overflow: hidden !important; margin: 0 !important; background: #000 !important; }
```

> Earlier versions injected CSS that hid the YouTube masthead and in-player
> overlays (end screens, pause overlay, "more videos"). That was removed when the
> app moved to the IFrame Player API, to comply with the YouTube API ToS.

## Technical Details

### Technologies Used
- **SwiftUI**: Modern UI framework
- **AppKit**: Menu bar integration and window management
- **WebKit**: YouTube video playback via WKWebView
- **Combine**: Reactive state management

### Window Levels
- `.floating`: Window stays above normal windows
- `.normal`: Standard window behavior

### Transparency Implementation
- Uses `window.alphaValue` for visual transparency (0.0 - 1.0)
- Uses `window.ignoresMouseEvents` for click-through behavior
- Combined with `.onHover` modifier for responsive interaction

### User Agent
```
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)
AppleWebKit/605.1.15 (KHTML, like Gecko)
Version/17.0 Safari/605.1.15
```

## Installation

1. Build the project in Xcode
2. Copy `YouTubePlayer.app` to `/Applications/`
3. Launch from Applications folder or Spotlight

## Usage

### Opening Videos
**Method 1: Drag & Drop**
- Drop a YouTube video/playlist URL, direct MP4/WebM URL, or local MP4/WebM file on the player window

**Method 2: Menu Bar**
- Click the menu bar icon → "Open URL..."
- Paste the supported video or playlist URL and click "Open"

**Method 3: Keyboard Shortcut**
- Press ⌘O to open the URL dialog

### Library Behavior
- If you open a link for a video that already exists in recent videos or watch history, the app updates the existing entry instead of creating a new one.
- The existing entry keeps its note, star rating, thumbs-down state, and saved timeline.
- If the same video is already the active player item, the app keeps the current entry and timeline intact instead of reloading a duplicate playback state.

### Watch History
- Open the Watch History window from the Player menu.
- Select a video to reopen it at the saved time.
- Add or edit notes directly from the history window.
- Mark a video with stars or a thumbs-down flag.
- Watch-history items are intended to persist; metadata should stay attached to the same video entry.

### Controlling Transparency
1. **Enable Hover Mode**: Click menu bar icon → "Toggle Transparency" (or press ⌘T)
2. Move mouse over window to make it transparent and click-through
3. Disable Hover Transparency with ⌘T when you want to use the on-window playback controls. Active dragging suppresses hover click-through.

### Opacity Presets
- **80% Transparency (clickable)**: Menu → "80% Transparency" (⌘8). Keeps the window interactive while semi-transparent.
- **25% Dimmer (clickable)**: Menu → "Toggle Opacity" (⌘P). Dims to 25% while keeping clicks active; press again to restore 100%.

### Window Behavior
- **Always On Top**: Enabled by default, toggle with ⌘L
- **Player Window Close**: Closing the player window stops playback/audio and closes only that window
- **Menu Bar Persistence**: The app remains available from the menu bar until Quit is chosen
- **Last URL Persistence**: The last played YouTube URL is reloaded on launch
- **Playback Position Persistence**: The last timeline position for each video is saved and reused

## Design Philosophy

### Minimalism
- No unnecessary UI elements
- Clean, distraction-free viewing
- Native controls with restrained visual chrome

### Non-Intrusive
- Hover transparency allows working with apps below
- Click-through when transparent
- Easy toggle between modes

### Quick Access
- Menu bar icon always available
- Keyboard shortcuts for common actions
- Drag & drop for instant playback

## Future Enhancements

Potential features for future versions:
- Picture-in-Picture mode
- Custom opacity levels (adjustable transparency)
- Multiple video windows
- Volume control from menu bar
- Window size presets
- Remember more window/layout presets
- Dark/Light theme support

## Requirements

- macOS 13.0 or later
- Xcode 15.0+ (for building)

## Rebuilding the App

1. Install Xcode 15+ and sign in with an Apple ID (for automatic signing).
2. Open `YouTubePlayer.xcodeproj` in Xcode.
3. Select the `YouTubePlayer` scheme and your target Mac under the run destination.
4. Build and run with `⌘R` for a debug build.

### Command-Line Build (Release)

You can also rebuild without opening Xcode:

```bash
xcodebuild \
  -project YouTubePlayer.xcodeproj \
  -scheme YouTubePlayer \
  -configuration Release \
  -derivedDataPath ./DerivedDataBuild \
  clean build
```

- The signed app will be at `DerivedDataBuild/Build/Products/Release/YouTubePlayer.app`.
- Copy it to `/Applications` (or wherever you prefer) to run it outside Xcode.

## Verification

See [Tests/README.md](Tests/README.md) for regression commands and manual checks. The September 16, 2026 Release build passed, along with media/drop and playlist bridge checks. Native checks covered MP4 playback and queue advancement; modern toolbar and playlist captures are in `build/UpdatedPlayer/verification/` when the packaged build is present. The original reported drag crash was not reproduced, so the drop changes are hardening rather than a confirmed reproduction-based fix. Full VoiceOver operation and measured contrast were not audited.

The locally packaged app is `build/UpdatedPlayer/YouTubePlayer.app`. UI tokens and implementation notes are in [design.md](design.md).

## License

This project is provided as-is for educational and personal use.

## Credits

Built with SwiftUI and WebKit for macOS.

## WebM playback

Local `.webm` files and direct HTTP(S) WebM URLs are supported by the native playback controls and saved queues. Drop a WebM onto the player or choose it through Playlist → Add Files. Playback depends on the codecs supported by the installed macOS WebKit; a generated VP9 WebM was verified to play, fill the viewport and emit completion on the development Mac.

## Zooming non-YouTube videos

Open Playback options (the sliders icon) and adjust **Video zoom** from 100% to 300%. **Reset to 100%** restores the original size. Zoom resets when a new source loads. MP4/WebM video and exposed side margins use a black canvas. YouTube keeps its existing player sizing controls.

### MKV playback

Choose MKV through Playlist → Add Files, drop a file onto the player, or paste a direct `.mkv` URL. The bundled VLCKit engine decodes the original media directly, including its audio. Playback uses the existing pause, seek, volume, zoom, resume history and playlist controls. No conversion or separate player installation is required.

Before building, run `sh Scripts/setup-vlckit.sh` to fetch the pinned official VLCKit framework. Xcode links and embeds it in the app.

For a local ad-hoc signed build, use `xcodebuild -project YouTubePlayer.xcodeproj -scheme YouTubePlayer -configuration Release -derivedDataPath /tmp/YouTubePlayerBuild ENABLE_HARDENED_RUNTIME=NO build`. Distribution builds can keep hardened runtime enabled when the app and embedded framework are signed with the same developer identity.
