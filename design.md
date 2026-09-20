# Player Design

This document describes the current native macOS player and its agreed behavior.
The user's player screenshot supplies the visual direction; subsequent requests
for smaller controls, video behind the top bar, playlist file deletion, shuffle,
and top-bar dragging during hover transparency take precedence over the original
screenshot's dimensions.

## Visual direction

Use the playing video as the main surface, with a centered title and a compact,
two-row floating control panel near the bottom. The timeline uses a coral-orange
played segment, a subdued remaining track, and a white circular scrubber.
Place volume on the left, transport controls in the center, and utilities on the
right. Keep native macOS window buttons and SF Symbols.

Video imagery and titles come from the actual media. The reference's boats and
sample filename are not app assets or fixed content.

## Colors and materials

| Element | Value |
| --- | --- |
| Panel | `#273849`, 94% opacity over ultra-thin material |
| Accent | `#FF694A` |
| Primary text and icons | White |
| Timestamps | White at 85% |
| Enabled timeline track | White at 35% |
| Disabled timeline track | White at 15% |
| Volume background and fill | White at 35% each, composited |
| Panel border | White at 6% |
| Panel shadow | Black at 20%, radius 12pt, downward offset 4pt |
| Active playlist row | Accent at 16% |
| Other playlist rows | White at 4% |

`PlayerChrome` owns the shared palette, panel dimensions, and typography tokens.

## Compact player controls

The compact dimensions below are the current specification, replacing the larger
control bar in the original reference.

| Element | Size or spacing |
| --- | --- |
| Panel height / corner radius | 72pt / 10pt |
| Panel outer inset | 8pt horizontally and below |
| Panel inner padding | 14pt horizontal, 8pt vertical |
| Timeline row / control row | 20pt / 28pt |
| Gap between rows | 4pt |
| Timeline track / scrubber diameter | 3pt / 12pt |
| Volume block | 88 × 26pt, 6pt corner radius |
| Utility and previous/next icons | 16pt semibold |
| Play/pause icon | 24pt semibold |
| Utility button hit area | 28 × 28pt |
| Play/pause hit area | 36 × 28pt |
| Transport spacing | 8pt |
| Timestamps | 11pt medium, monospaced digits |

Show elapsed time and total duration at opposite ends of the timeline. Disable
seeking when duration is unavailable. Previous and next buttons use the existing
playlist actions and are disabled when no corresponding item is available.

At toolbar widths of 480pt or more, show the volume block, fullscreen,
always-on-top, playback settings, and playlist controls. Below 480pt, use a mute
button and keep fullscreen and always-on-top available in playback settings.
Keep transport centered independently of the side groups.

Playback settings includes volume, fullscreen, always-on-top, and video zoom for
supported non-YouTube playback. The utilities reflect supported app functions;
separate AirPlay and picture-in-picture engines are outside this UI change.

## Title and top bar

Video extends to the top window edge behind the native window buttons. The main
scene uses the hidden-titlebar window style, and the player ignores the titlebar
safe area. Keep a 28pt opaque black backing strip underneath the video at the top,
so this area does not expose the desktop when video opacity changes.

Use a 24pt semibold system-font title, centered within a 36pt row with a 40pt top
inset and 24pt horizontal padding. Keep it on one line with middle truncation and
retain the full title in the view's text/help. Apply a subtle dark text shadow.

| Top-bar element | Token / value |
| --- | --- |
| Opaque backing and drag-strip height | `PlayerChrome.topBarHeight` / 28pt |
| Leading space reserved for window buttons | `PlayerChrome.windowButtonsWidth` / 80pt |

Outside hover-transparency mode, the title and playback controls appear while
hovered, paused, or scrubbing. They are hidden while hover transparency is enabled;
the native window buttons and top drag strip remain available.

The top 28pt strip remains interactive in hover-transparency mode: entering it
restores the video and mouse input for the native window buttons and window
dragging. Hovering over the video below this strip hides the video and passes
clicks through, while the top backing stays opaque. Leaving the window restores
the video and mouse input. Do not enter click-through mode during a mouse drag
or when the player is a file-drop target.

Use a native window-drag surface across the strip, reserving the leading 80pt
for the macOS window buttons. A first click can start dragging even when the
window is inactive. Re-evaluate hover boundaries against the current window frame
as it moves or resizes, including on monitors with negative screen coordinates.

## Playlist

Use a dark slate sheet with the same coral accent, white text, a 24pt semibold
heading, 24pt outer padding, and rounded row highlights. Row titles use native
body typography with medium weight; metadata uses native caption typography.
Highlight the currently playing entry with the accent tint and a speaker icon.

Provide:

- Add URL and Add Files actions for supported media.
- Play, move up, move down, and remove-from-playlist row actions.
- Clear Playlist, Shuffle, and Done actions in the footer.
- An empty state explaining how to add videos.
- Visible error messages when adding or trashing a file fails.

### Removing entries and original files

Keep these actions separate:

- **Remove from playlist:** remove only the selected entry; leave the file intact.
- **Move Original File to Trash:** available for local video files, with a
  confirmation that names the file and explains that the original moves to macOS
  Trash and can be restored from there.

Only local regular MP4, WebM, and MKV files can be trashed. Reject remote URLs,
directories, unsupported files, and missing files. Use the macOS Trash operation,
not permanent deletion. Cancellation changes nothing. On failure, preserve the
playlist and show the error. After success, remove matching playlist references,
stop playback if it was the active file, and remove its saved position and history.

### Shuffle

The footer's Shuffle menu offers:

- **Shuffle all videos:** randomize the entire visible playlist order.
- **Shuffle remaining videos:** preserve the current entry and preceding entries,
  and randomize only those after the current video.

Disable all-shuffle with fewer than two entries. Disable remaining-shuffle when
there is no current playlist position or fewer than two upcoming entries.
Shuffling changes the saved playlist order without restarting current playback;
the active-item highlight follows the playing video to its new position.

## Playback and keyboard behavior

- **Space:** play or pause; holding Space does not repeatedly toggle playback.
- **Left / Right:** seek backward or forward by five seconds.
- Preserve text editing, dialog input, and native slider keyboard interaction.
- Save playback positions per video in local persistent preferences and restore
  them when reopening media, including after restarting the app.
- Restore local-video positions after metadata is ready; initial loading must not
  overwrite the saved position with zero.
- Save YouTube pause updates promptly and resume without the former five-second
  rewind.

## Components, accessibility, and motion

`PlayerToolbar` composes the timeline, transport, volume, and utility controls.
`PlayerSlider` wraps a native `NSSlider` with custom drawing, retaining native
mouse interaction and accessible slider values. `PlaylistView` owns the playlist
sheet and confirmations; playback and successful file-removal callbacks connect
to `ContentView`.

`PlayerWindowDragArea` provides the top strip's native AppKit drag surface and
forwards mouse-down events to `NSWindow.performDrag(with:)`.
`PlayerWindowCoordinator.isPointerOverPlayback` excludes the top strip from the
hover click-through region. The existing 0.15-second hover monitor restores input
when the pointer returns from the transparent video area to the top strip.

Use named buttons, tooltips, readable contrast, monospaced timestamps, and native
focus behavior. Hide decorative speaker imagery from accessibility. Support
Unicode titles and truncate rather than wrapping over the video. Respect Reduce
Motion for the existing 0.18-second control-overlay opacity transition.

## Verification and delivery

Verify the native app through its actual macOS UI. Browser-only Lighthouse and
React tooling do not apply to this SwiftUI/AppKit surface.

The implementation was checked at 790 × 444pt and 376 × 212pt player sizes, plus
the playlist, playback settings, and file-Trash confirmation. Live checks covered
seeking, Space/arrow controls, volume, adding entries, both shuffle choices, and
cancelling file deletion. A disposable-file test exercised the actual Trash
operation and rejection of remote URLs, directories, and missing files.

Release builds, code-signature verification, and playback/playlist bridge
regression checks passed. The app was copied to `/Applications/YouTubePlayer.app`
and launched, with the previous installation backed up.

The latest top-bar update was rebuilt, copied to Applications, and launched on
2026-09-20. Release compilation and strict code-signature verification passed.
All three Node test files passed, including the Swift/AppKit hover test covering
wide and compact frames, negative screen coordinates, top-strip boundaries,
inactive-window first clicks, and forwarding to the native drag API. The code
review found no blockers.

Live end-to-end dragging with hover transparency still needs a measured
before/after window-position check. Automated UI input was stopped while the
user was interacting with the player; the regression tests do not replace that
remaining manual check.

Evidence and review reports:

- `.omo/evidence/player-ui/verification.md`
- `.omo/evidence/player-ui/`
- `.omo/evidence/native-player-ui-gate-review.md`
- `.omo/evidence/native-player-ui-clone-fidelity.md`
- `.omo/evidence/hover-top-bar/verification.md`
- `.omo/evidence/hover-top-bar-code-review.md`
