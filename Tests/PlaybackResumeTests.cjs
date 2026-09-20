const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const swift = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/ContentView.swift'), 'utf8');
const script = swift.split('let progressTrackingScript = WKUserScript(')[1].split('source: """')[1].split('"""')[0];
const messages = [];
const listeners = {};
const video = {
  readyState: 0, currentTime: 0, duration: 120, paused: true,
  style: {}, classList: { remove() {} },
  addEventListener(name, callback) { listeners[name] = callback; }
};
const location = { hostname: '', pathname: '/movie.webm', href: 'file:///movie.webm', search: '' };
const context = {
  window: {
    nativeResumeTime: 67,
    location,
    webkit: { messageHandlers: {
      videoProgress: { postMessage: value => messages.push(value) },
      playerBridge: { postMessage() {} }
    } },
    addEventListener() {}
  },
  document: {
    title: 'Movie', documentElement: { style: {} }, body: { style: {} },
    querySelector: selector => selector === 'video' ? video : null,
    querySelectorAll: () => [video], addEventListener() {}
  },
  URLSearchParams, setInterval() {}, MutationObserver: class { observe() {} }
};
vm.runInNewContext(script, context);
assert.equal(messages.length, 0, 'Loading must not overwrite the saved position with zero');
video.readyState = 1;
listeners.loadedmetadata();
assert.equal(video.currentTime, 67, 'Restore the saved position when metadata is ready');
assert.equal(messages.at(-1).currentTime, 67);
video.currentTime = 83;
listeners.pause();
assert.equal(messages.at(-1).currentTime, 83, 'Save the stopped position immediately');
video.currentTime = 0;
listeners.seeked();
assert.equal(messages.at(-1).currentTime, 0, 'Allow intentionally returning to the beginning');
console.log('Playback resume checks passed');
