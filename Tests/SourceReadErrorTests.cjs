const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const script = source.split('let progressTrackingScript = WKUserScript(')[1].split('source: """')[1].split('"""')[0];
const messages = [];
const progress = [];
const listeners = {};
const video = {error: {code: 2}, readyState: 0, currentTime: 0, duration: NaN, style: {}, classList: {remove() {}}, addEventListener(name, fn) {listeners[name] = fn;}};
const location = {hostname: '', pathname: '/broken.mp4', href: 'file:///broken.mp4', search: ''};
const context = {
  window: {location, nativeSourceURL: 'https://example.com/original.mp4', nativeResumeTime: 67, addEventListener() {}, webkit: {messageHandlers: {
    playerBridge: {postMessage: value => messages.push(value)}, videoProgress: {postMessage: value => progress.push(value)}
  }}},
  document: {title: 'Broken', documentElement: {style: {}}, body: {style: {}}, querySelector: () => video,
    querySelectorAll: () => [video], addEventListener() {}},
  URLSearchParams, setInterval() {}, MutationObserver: class {observe() {}}
};
vm.runInNewContext(script, context);
assert.equal(messages.length, 1, 'Report a read error even before metadata is ready');
assert.equal(messages[0].event, 'mediaError');
assert.equal(messages[0].code, 2);
assert.equal(messages[0].sourceURL, context.window.nativeSourceURL, 'Redirects retain the originally requested source identity');
assert.equal(progress.length, 0, 'An unreadable source must not overwrite saved progress');
listeners.error();
assert.equal(messages.length, 1, 'Deduplicate the same failure');
video.error = {code: 1};
listeners.error();
assert.equal(messages.length, 1, 'Intentional abort is not a source failure');
video.error = null;
video.readyState = 1;
video.duration = 120;
video.paused = true;
listeners.loadedmetadata();
assert.equal(video.currentTime, 67, 'Recovery restores the original saved position');
video.error = {code: 3};
listeners.error();
assert.equal(messages.at(-1).code, 3, 'Detect later decode errors');
console.log('Source read error bridge checks passed');
