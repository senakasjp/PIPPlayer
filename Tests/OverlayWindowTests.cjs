const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const start = source.indexOf('    private func applyAlwaysOnTopState(');
const end = source.indexOf('    private func reassertAlwaysOnTopState(', start);
if (start < 0 || end < 0) throw new Error('Window level methods not found');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'player-overlay-'));
try {
  fs.writeFileSync(path.join(directory, 'main.swift'), `
import AppKit
final class Harness {
    var isAlwaysOnTop = true
    var showingPlaylist = false
    var overlayPresentationCount = 0
    let alwaysOnTopLevel = NSWindow.Level.statusBar
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    func getWindow() -> NSWindow? { window }
    func isPlayerWindow(_ window: NSWindow) -> Bool { true }
    func isWindowReadyForLevelChanges(_ window: NSWindow) -> Bool { true }
${source.slice(start, end).replaceAll('private func', 'func')}
}
let app = NSApplication.shared
let harness = Harness()
func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
harness.showingPlaylist = true
harness.suspendAlwaysOnTopForOverlay()
harness.applyAlwaysOnTopState(harness.window)
drain()
precondition(harness.window.level == .normal, "Focus reassertion must not cover the playlist or browse dialog")
harness.suspendAlwaysOnTopForOverlay()
harness.restoreAlwaysOnTopAfterOverlay()
drain()
precondition(harness.window.level == .normal, "Closing a nested dialog must keep the playlist above the player")
harness.showingPlaylist = false
harness.restoreAlwaysOnTopAfterOverlay()
drain()
precondition(harness.window.level == .statusBar, "Last dialog dismissal restores always on top")
harness.isAlwaysOnTop = false
harness.applyAlwaysOnTopState(harness.window)
drain()
precondition(harness.window.level == .normal, "Disabled always on top remains disabled")
print("Overlay focus and nested dismissal checks passed")
`);
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc', [
    '-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk',
    '-module-cache-path', path.join(directory, 'cache'), path.join(directory, 'main.swift'), '-o', path.join(directory, 'test'),
  ], { stdio: 'inherit' });
  execFileSync(path.join(directory, 'test'), [], { stdio: 'inherit' });
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
