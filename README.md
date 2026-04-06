# YouTube Player

A macOS YouTube mini-player with a persistent menu bar control surface, playback restore, and lightweight watch library metadata.

## Features

### Playback
- **Open YouTube URLs**: Paste, drop, or enter a YouTube link to start playback or replace the current video
- **Last Video Restore**: Remembers the last opened video and restores it on launch
- **Resume Playback Position**: Stores timeline progress per video and resumes from the saved time
- **Minimal Viewing UI**: Hides scrollbars and trims YouTube chrome for a cleaner player

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
- **Fill Player Window**: Expands the video view for a cleaner watch surface
- **16:9 Resize Lock**: Optional aspect-ratio lock while resizing
- **Close Window Without Quitting**: Closing the player window stops audio and closes the window, but keeps the menu bar app running until you quit explicitly

### Controls

#### Menu Bar Icon
Click the play button icon in the menu bar to access:
- **Open URL...** (⌘O) - Open a YouTube video by URL
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
- **State Management**: Tracks transparency mode, hover state, active playback, and window level
- **Window Configuration**: Sets up transparent titlebar and floating behavior
- **Playback Restore**: Reloads the last saved video and playback position
- **Progress Persistence**: Saves timeline progress back into app state and user defaults
- **Hover Detection**: Uses `.onHover` modifier to detect mouse position
- **Window Manipulation**: Controls alpha value and mouse event pass-through

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

### CSS Customization

The app injects custom CSS to enhance the YouTube viewing experience:

```css
/* Hide scrollbars */
::-webkit-scrollbar { display: none !important; }

/* Remove overflow */
body { overflow: hidden !important; margin: 0 !important; }
html { overflow: hidden !important; }

/* Hide YouTube header */
#masthead-container { display: none !important; }

/* Theater mode optimization */
ytd-watch-flexy[theater] #player-theater-container.ytd-watch-flexy {
    max-width: 100% !important;
    width: 100% !important;
}
```

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
- Drag any YouTube URL and drop it on the player window

**Method 2: Menu Bar**
- Click the menu bar icon → "Open URL..."
- Paste the YouTube URL and click "Open"

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
3. Move mouse away to interact with the player

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
- Hidden YouTube interface elements

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
- Playlist support
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

## License

This project is provided as-is for educational and personal use.

## Credits

Built with SwiftUI and WebKit for macOS.
