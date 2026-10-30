const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const source = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const property = source.match(/private var barsVisible: Bool \{[^}]+\}/)[0];
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'disney-toolbar-'));
try {
  const file = path.join(directory, 'main.swift');
  fs.writeFileSync(file, `
struct Visibility {
    var isHovering = false
    var isScrubbing = false
    var playerState = -1
    var currentVideoID: String? = "disneyplus:/en-gb/play/example"
    ${property.replace('private ', '')}
}
var state = Visibility()
precondition(!state.barsVisible, "Disney toolbar must hide outside the window even without playback telemetry")
state.isHovering = true
precondition(state.barsVisible)
state.isHovering = false
state.isScrubbing = true
precondition(state.barsVisible)
state.isScrubbing = false
state.currentVideoID = "youtube-example"
precondition(state.barsVisible, "YouTube loading controls remain available")
state.playerState = 1
precondition(!state.barsVisible)
print("Disney toolbar visibility checks passed")
`);
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift', ['-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk', '-target', 'arm64-apple-macosx14.0', '-module-cache-path', path.join(directory, 'cache'), file], {stdio: 'inherit'});
} finally {
  fs.rmSync(directory, {recursive: true, force: true});
}
