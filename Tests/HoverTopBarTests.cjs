const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const coordinator = source.split('final class PlayerWindowCoordinator:')[1].split('/// Serves player.html')[0];
const webView = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/WebView.swift'), 'utf8');
const dragArea = webView.slice(webView.indexOf('struct PlayerWindowDragArea:'), webView.indexOf('struct WebView:'));
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'player-hover-test-'));
try {
  const file = path.join(directory, 'main.swift');
  fs.writeFileSync(file, `import AppKit
import SwiftUI
${dragArea}
final class PlayerWindowCoordinator:${coordinator}
let frames = [NSRect(x: 100, y: 200, width: 790, height: 444), NSRect(x: -800, y: -200, width: 376, height: 212)]
for frame in frames {
    func hit(_ x: CGFloat, _ y: CGFloat) -> Bool {
        PlayerWindowCoordinator.isPointerOverPlayback(NSPoint(x: x, y: y), contentRect: frame, windowFrame: frame, topBarHeight: 28)
    }
    precondition(!hit(frame.minX + 12, frame.maxY - 12), "Window buttons must remain interactive")
    precondition(!hit(frame.midX, frame.maxY - 20), "Top-bar dragging must remain interactive")
    precondition(!hit(frame.midX, frame.maxY - 28), "Top-bar boundary must not pass through")
    precondition(hit(frame.midX, frame.maxY - 29), "Video below the bar must still pass through")
    precondition(hit(frame.midX, frame.midY), "Video center must still pass through")
    precondition(!hit(frame.minX - 1, frame.midY), "Outside the window must restore input")
}
let app = NSApplication.shared
final class TestWindow: NSWindow {
    var dragStarted = false
    override func performDrag(with event: NSEvent) { dragStarted = true }
}
let window = TestWindow(contentRect: frames[0], styleMask: [.titled], backing: .buffered, defer: false)
let dragView = PlayerWindowDragArea.DragView()
window.contentView = dragView
precondition(dragView.acceptsFirstMouse(for: nil), "Dragging must work on an inactive window")
let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
dragView.mouseDown(with: event)
precondition(window.dragStarted, "Top-bar mouse-down must start native window dragging")
print("Hover top-bar checks passed at large, compact, and negative-screen coordinates")
`);
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift', ['-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk', '-target', 'arm64-apple-macosx14.0', '-module-cache-path', path.join(directory, 'cache'), file], {stdio: 'inherit'});
} finally {
  fs.rmSync(directory, {recursive: true, force: true});
}
