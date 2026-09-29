const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const source = fs.readFileSync(process.argv[2] === '-' ? 0 : (process.argv[2] || path.join(__dirname, '../YouTubePlayer/ContentView.swift')), 'utf8');
const toolbar = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/PlayerToolbar.swift'), 'utf8');
const topBar = source.slice(source.indexOf('    private var playerTopBar:'), source.indexOf('    private var playerControlBar:'));
const start = source.indexOf('    var body: some View {');
let body = source.slice(start, source.indexOf('        .overlay(alignment: .top)', start));
const webStart = body.indexOf('            WebView(');
const webEnd = body.indexOf('\n            Color.clear.overlay', webStart);
// Replace only the media surface; exercise the production status/chrome layout.
// Older versions put the conditional status directly in the root ZStack.
const statusStart = body.indexOf('\n            if statusMessage', webStart);
const end = statusStart >= 0 && statusStart < webEnd ? statusStart : webEnd;
if (start < 0 || webStart < 0 || end < 0) throw new Error('Player layout boundaries changed');
body = body.slice(0, webStart) + '            Color.black\n' + body.slice(end) + '\n    }';
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'player-window-layout-'));
try {
  const file = path.join(directory, 'main.swift');
  fs.writeFileSync(file, `import SwiftUI
import AppKit
${toolbar}
struct LayoutFixture: View {
    let statusMessage: String
    let isDropTargeted = false
    let barsVisible = true
    let isTransparent = false
    let reduceMotion = true
    let currentVideoTitle = "A long video title"
${topBar}
    var playerControlBar: some View {
        PlayerToolbar(isPlaying: false, currentTime: .constant(12), duration: 60,
                      volume: .constant(1), isScrubbing: .constant(false),
                      onToggle: {}, onSeek: {}, onPlaylist: {})
            .padding(.horizontal, PlayerChrome.inset)
            .padding(.bottom, PlayerChrome.inset)
    }
${body}
}
let app = NSApplication.shared
for message in ["", "Playing video", String(repeating: "A long video filename with several words ", count: 8)] {
    let host = NSHostingController(rootView: LayoutFixture(statusMessage: message))
    for width: CGFloat in [280, 326, 600] {
        let height = round(width * 9 / 16)
        let fitted = host.sizeThatFits(in: NSSize(width: width, height: height))
        precondition(fitted.height <= height + 1, "Status/chrome forces window from \\(height) to \\(fitted.height) at width \\(width)")
    }
}
print("Player layout stays within compact 16:9 bounds for empty, short and long status messages")
`);
  const executable = path.join(directory, 'layout-tests');
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc', [
    '-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk',
    '-module-cache-path', path.join(directory, 'cache'), file, '-o', executable,
  ], { stdio: 'inherit' });
  execFileSync(executable, [], { stdio: 'inherit' });
} finally {
  fs.rmSync(directory, { recursive: true, force: true });
}
