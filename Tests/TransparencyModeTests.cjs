const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const content = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const app = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/YouTubePlayerApp.swift'), 'utf8');

// The player must start from the saved preference. Starting from `true` let
// hover click-through run while the menu item was off when the window was not
// ready during launch.
assert.match(content, /@State private var isTransparent = AppSettings\.shared\.hoverTransparencyEnabled/);
assert.match(content, /@State private var isEightyTransparency = AppSettings\.shared\.eightyTransparencyEnabled/);
assert.match(content, /applyCurrentTransparencyState\(to: window\)/, 'Window setup must re-apply the saved opacity mode');
assert.match(content, /private func applyCurrentTransparencyState/, 'Saved opacity mode must be re-applied after launch');
assert.match(app, /@Published var hoverTransparencyEnabled: Bool = false/, 'Hover transparency must be off by default');
assert.match(content, /isAlreadyTerminating[\s\S]*?NSApp\.terminate\(nil\)/, 'Closing the player window must quit the whole app');
assert.match(app, /func applicationShouldTerminate\(_ sender: NSApplication\)[\s\S]*?isTerminating = true/, 'Quit must not start a second termination pass');

const eighty = content.slice(content.indexOf('    func setEightyTransparency('), content.indexOf('    func setHoverTransparency('));
const hover = content.slice(content.indexOf('    func setHoverTransparency('), content.indexOf('    func setFillPlayerWindow('));
if (!eighty.includes('func setEightyTransparency') || !hover.includes('func setHoverTransparency')) {
  throw new Error('Transparency setters not found');
}

const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'player-transparency-'));
try {
  const file = path.join(directory, 'main.swift');
  fs.writeFileSync(file, `
struct DispatchQueue {
    static let main = DispatchQueue()
    func async(execute: () -> Void) { execute() }
}
final class Settings {
    var hoverTransparencyEnabled = false
}
final class Window {
    var ignoresMouseEvents = false
}
final class Harness {
    var isEightyTransparency = false
    var isDimmed = false
    var isTransparent = false
    var isHovering = false
    var contentOpacity: Double = 1
    var settings = Settings()
    var window: Window? = Window()
    func getWindow() -> Window? { window }
    func applyTransparentWindowAppearance(_ window: Window, isFullyTransparent: Bool) {}
    func applyTransparentSurfaceMode() {}
    func ensureWindowFront(_ window: Window) {}
    func setStatusMessage(_ message: String) {}
    func startHoverMonitor(for window: Window) {}
    func stopHoverMonitor() {}
    func updateHoverStateFromMouseLocation(window: Window) { isHovering = true }
${eighty}
${hover}
}
let player = Harness()
player.settings.hoverTransparencyEnabled = true
player.isTransparent = true
player.setEightyTransparency(to: false)
precondition(player.settings.hoverTransparencyEnabled, "Turning 80% transparency off must not disable hover transparency")
precondition(player.isTransparent, "Turning 80% transparency off must not clear the hover-transparency state")

player.setHoverTransparency(to: false)
precondition(!player.isTransparent, "Hover transparency must be disabled even before the window is available")
player.window = nil
player.isTransparent = true
player.setHoverTransparency(to: false)
precondition(!player.isTransparent, "A missing window must not leave stale hover-transparency state")
player.window = Window()
player.setEightyTransparency(to: true)
precondition(player.isEightyTransparency, "80% transparency mode must be stored")
precondition(!player.settings.hoverTransparencyEnabled, "80% transparency must turn off hover transparency")
precondition(player.contentOpacity == 0.2, "80% transparency must set the window content to 20% opacity")
print("Transparency mode state checks passed");
`);
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift', [
    '-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk',
    '-target', 'arm64-apple-macosx14.0', '-module-cache-path', path.join(directory, 'cache'), file,
  ], { stdio: 'inherit' });
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
