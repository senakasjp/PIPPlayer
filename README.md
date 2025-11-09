# YouTube Player

A minimalist, floating YouTube player for macOS with hover-based transparency and always-on-top functionality.

## Features

### Core Functionality
- **Floating Window**: Always stays on top of other applications (toggleable)
- **Hover Transparency**: Window becomes 90% transparent and click-through when you hover over it
- **Menu Bar Control**: Quick access to all features via a menu bar icon
- **Drag & Drop**: Simply drag YouTube URLs onto the player window
- **Minimal UI**: Clean interface with hidden scrollbars and YouTube header

### Controls

#### Menu Bar Icon
Click the play button icon in the menu bar to access:
- **Open URL...** (⌘O) - Open a YouTube video by URL
- **Toggle Transparency** (⌘T) - Enable/disable hover transparency mode
- **Toggle Always On Top** (⌘L) - Control whether window floats above others
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
- **Notification System**: Uses NotificationCenter to communicate with ContentView

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    // Creates menu bar icon with play.rectangle.fill symbol
    // Manages menu items and keyboard shortcuts
}
```

#### 2. Content View (ContentView.swift)
- **State Management**: Tracks transparency mode, hover state, and window level
- **Window Configuration**: Sets up transparent titlebar and floating behavior
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

### Controlling Transparency
1. **Enable Hover Mode**: Click menu bar icon → "Toggle Transparency" (or press ⌘T)
2. Move mouse over window to make it transparent and click-through
3. Move mouse away to interact with the player

### Window Behavior
- **Always On Top**: Enabled by default, toggle with ⌘L
- **Transparent Titlebar**: Window controls blend seamlessly
- **Black Background**: Clean viewing experience

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
- Remember last position/size
- Dark/Light theme support

## Requirements

- macOS 13.0 or later
- Xcode 15.0+ (for building)

## License

This project is provided as-is for educational and personal use.

## Credits

Built with SwiftUI and WebKit for macOS.
