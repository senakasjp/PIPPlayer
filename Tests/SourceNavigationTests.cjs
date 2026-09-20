const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const source = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const handler = 'final class YouTubeScriptMessageHandler:' + source.split('final class YouTubeScriptMessageHandler:')[1].split('final class PlayerWindowCoordinator:')[0];
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'player-source-test-'));
try {
  const file = path.join(directory, 'main.swift');
  fs.writeFileSync(file, `import AppKit
import WebKit
${handler}
let handler = YouTubeScriptMessageHandler()
for code in [102, 204] {
    precondition(!YouTubeScriptMessageHandler.shouldReportNavigationError(NSError(domain: "WebKitErrorDomain", code: code)), "Normal media handoffs are not failures")
}
precondition(!YouTubeScriptMessageHandler.shouldReportNavigationError(URLError(.cancelled) as NSError))
precondition(YouTubeScriptMessageHandler.shouldReportNavigationError(URLError(.cannotOpenFile) as NSError))
precondition(YouTubeScriptMessageHandler.shouldReportNavigationError(URLError(.notConnectedToInternet) as NSError))
_ = NSApplication.shared
let web = WKWebView()
let oldNavigation = web.loadHTMLString("old", baseURL: nil)!
let currentNavigation = web.loadHTMLString("current", baseURL: nil)!
handler.webView(web, didStartProvisionalNavigation: currentNavigation)
var failures = 0
handler.onNavigationError = { _ in failures += 1 }
handler.webView(web, didFailProvisionalNavigation: oldNavigation, withError: URLError(.cannotOpenFile))
precondition(failures == 0, "Ignore errors from replaced navigation")
handler.webView(web, didFailProvisionalNavigation: currentNavigation, withError: URLError(.cancelled))
precondition(failures == 0, "Ignore intentional cancellation")
handler.webView(web, didFailProvisionalNavigation: currentNavigation, withError: URLError(.cannotOpenFile))
precondition(failures == 1, "Report current source read failure")
print("Native source navigation error checks passed")
`);
  execFileSync('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift', ['-sdk', '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk', '-target', 'arm64-apple-macosx14.0', '-module-cache-path', path.join(directory, 'cache'), file], {stdio: 'inherit'});
} finally {
  fs.rmSync(directory, {recursive: true, force: true});
}
