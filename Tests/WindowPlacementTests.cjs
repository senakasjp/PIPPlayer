const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

// The window placement helpers live with the shared player chrome. Compile them
// with a minimal equalizer stub so the test exercises the production AppKit code.
const toolbar = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/PlayerToolbar.swift'), 'utf8');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'player-window-placement-'));
try {
  const file = path.join(directory, 'main.swift');
  fs.writeFileSync(file, `
import SwiftUI
import AppKit

final class PlayerEqualizer: ObservableObject {
    static let frequencies = ["63 Hz", "250 Hz", "500 Hz", "1.5 kHz", "3 kHz", "5 kHz", "8 kHz"]
    @Published var isEnabled = false
    @Published var gains = Array(repeating: 0.0, count: 7)
    @Published var errorMessage: String?
    func setGain(_ value: Double, at index: Int) { gains[index] = value }
    func resetGains() { gains = Array(repeating: 0.0, count: 7) }
}

${toolbar}

let app = NSApplication.shared
guard let screen = NSScreen.main ?? NSScreen.screens.first else {
    fatalError("A screen is required to verify window placement")
}
let visible = screen.visibleFrame
func makeWindow(_ frame: NSRect) -> NSWindow {
    let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.setFrame(frame, display: false)
    return window
}
func requireVisible(_ window: NSWindow, _ label: String) {
    precondition(visible.contains(window.frame), "\\(label): \\(window.frame) must stay inside \\(visible)")
}

// A window hanging over the right edge is pulled back inside.
let partlyOffscreen = makeWindow(NSRect(x: visible.maxX - 120, y: visible.midY, width: 400, height: 300))
partlyOffscreen.clampToVisibleScreen()
requireVisible(partlyOffscreen, "partly offscreen")

// A window on a disconnected display is brought back and centered.
let lost = makeWindow(NSRect(x: visible.maxX + 800, y: visible.maxY + 400, width: 400, height: 300))
lost.clampToVisibleScreen(centerIfOffscreen: true)
requireVisible(lost, "entirely offscreen")
precondition(abs(lost.frame.midX - visible.midX) <= 1 && abs(lost.frame.midY - visible.midY) <= 1,
             "An offscreen window should be centered, got \\(lost.frame)")

// A window bigger than the display is shrunk to the usable area.
let oversized = makeWindow(NSRect(x: visible.minX, y: visible.minY, width: visible.width + 500, height: visible.height + 500))
oversized.clampToVisibleScreen()
requireVisible(oversized, "oversized")

// A window already inside the display is left exactly where it is.
let control = makeWindow(NSRect(x: visible.minX + 40, y: visible.minY + 40, width: 320, height: 180))
let before = control.frame
control.clampToVisibleScreen()
precondition(control.frame == before, "An on-screen window must not move, got \\(control.frame)")

// Centering fits the window inside and puts it in the middle of the screen.
let centered = makeWindow(NSRect(x: visible.minX, y: visible.minY, width: visible.width + 200, height: 300))
centered.centerOnVisibleScreen()
requireVisible(centered, "centered")
precondition(abs(centered.frame.midX - visible.midX) <= 1, "Centered window should be horizontally centered")

print("Window placement checks passed: clamp, recover offscreen, fit oversized, preserve on-screen, center")
`);
  const executable = path.join(directory, 'placement-tests');
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc', [
    '-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk',
    '-module-cache-path', path.join(directory, 'cache'), file, '-o', executable,
  ], { stdio: 'inherit' });
  execFileSync(executable, [], { stdio: 'inherit' });
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
