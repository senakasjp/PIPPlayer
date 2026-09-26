const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const handler = source.slice(source.indexOf('    func handleHoverChange('), source.indexOf('    private func startHoverMonitor('));
assert.ok(handler.includes('func handleHoverChange'));
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'player-hover-click-'));
try {
  const file = path.join(directory, 'main.swift');
  fs.writeFileSync(file, `
struct DispatchQueue {
    static let main = DispatchQueue()
    func async(execute: () -> Void) { execute() }
}
struct NSEvent { static var pressedMouseButtons = 0 }
final class Window {
    var ignoresMouseEvents = false
    var attachedSheet: Int? = nil
}
final class Harness {
    var isTransparent = true
    var isDropTargeted = false
    var showsSourceError = false
    var contentOpacity: Double = 1
    var activations = 0
    let window = Window()
    func getWindow() -> Window? { window }
    func ensureWindowFront(_ window: Window) { activations += 1 }
    func applyTransparentWindowAppearance(_ window: Window, isFullyTransparent: Bool) {}
    func applyTransparentSurfaceMode() {}
${handler}
}
let player = Harness()
player.handleHoverChange(true)
precondition(player.window.ignoresMouseEvents && player.contentOpacity == 0)
for buttons in [1, 2, 4] {
    NSEvent.pressedMouseButtons = buttons
    player.handleHoverChange(true)
    precondition(player.window.ignoresMouseEvents && player.contentOpacity == 0, "Held background click must keep passing through")
    player.handleHoverChange(false)
    precondition(player.window.ignoresMouseEvents, "Background drag must retain input until release")
}
NSEvent.pressedMouseButtons = 0
player.handleHoverChange(false)
precondition(!player.window.ignoresMouseEvents && player.contentOpacity == 1)
precondition(player.activations == 0, "Hover must not steal focus from background app")
NSEvent.pressedMouseButtons = 1
player.handleHoverChange(true)
precondition(!player.window.ignoresMouseEvents, "Player drag must retain input until release")
NSEvent.pressedMouseButtons = 0
player.isDropTargeted = true
player.handleHoverChange(true)
precondition(!player.window.ignoresMouseEvents)
player.isDropTargeted = false
player.showsSourceError = true
player.handleHoverChange(true)
precondition(!player.window.ignoresMouseEvents)
player.showsSourceError = false
player.window.attachedSheet = 1
player.handleHoverChange(true)
precondition(!player.window.ignoresMouseEvents)
print("Hover click-through gesture and focus checks passed")
`);
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift', ['-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk', '-target', 'arm64-apple-macosx14.0', '-module-cache-path', path.join(directory, 'cache'), file], {stdio: 'inherit'});
} finally {
  fs.rmSync(directory, {recursive: true, force: true});
}
