const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');

const messages = [];
const calls = [];
let index = 0;
const context = {
  window: {
    addEventListener() {},
    webkit: { messageHandlers: { playerBridge: { postMessage: message => messages.push(message) } } }
  },
  document: { createElement() { return {}; }, head: { appendChild() {} } },
  fetch() { return Promise.reject(new Error('Offline test')); },
  setInterval() { return 1; }
};
vm.createContext(context);
const html = fs.readFileSync(path.join(__dirname, '../YouTubePlayer/player.html'), 'utf8');
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const api = context.window;
api.ytLoad('youtube-playlist:PLtest', 12, true, 3);
assert.equal(context.pending.index, 3);
context.player = {
  loadPlaylist: options => calls.push(['load', options]),
  cuePlaylist: options => calls.push(['cue', options]),
  loadVideoById: options => calls.push(['video', options]),
  nextVideo: () => calls.push(['next']),
  previousVideo: () => calls.push(['previous']),
  getVideoData: () => ({ video_id: 'abc', title: 'Example' }),
  getPlaylistIndex: () => index,
  getPlaylist: () => ['abc', 'def']
};
context.onReady();
assert.equal(calls[0][0], 'load');
assert.equal(calls[0][1].list, 'PLtest');
assert.equal(calls[0][1].index, 3);
assert.equal(calls[0][1].startSeconds, 12);
api.ytNext();
api.ytPrevious();
assert.equal(calls[1][0], 'next');
assert.equal(calls[2][0], 'previous');
api.ytLoad('youtube-playlist:PLother', 0, false, 1);
assert.equal(calls[3][0], 'cue');
context.onStateChange({ data: 0 });
assert(!messages.some(message => message.event === 'playlistEnded'));
index = 1;
context.onStateChange({ data: 0 });
assert.equal(messages.at(-1).event, 'playlistEnded');
assert.equal(messages.at(-1).playlistId, 'PLother');
api.ytLoad('abc', 7, true);
assert.equal(calls[4][0], 'video');
assert.equal(calls[4][1].startSeconds, 7);
api.ytNext();
assert.equal(calls.length, 5);
context.onStateChange({ data: 0 });
assert.equal(messages.at(-1).event, 'state');
console.log('Playlist bridge regression checks passed');

let playbackTime = 20;
let duration = 60;
context.player.getCurrentTime = () => playbackTime;
context.player.getDuration = () => duration;
context.player.seekTo = (time, allowSeekAhead) => {
  assert.equal(allowSeekAhead, true);
  playbackTime = time;
};
api.ytSeekRelative(5);
assert.equal(playbackTime, 25);
api.ytSeekRelative(5);
assert.equal(playbackTime, 30, 'Repeated arrows use the latest player position');
api.ytSeekRelative(-5);
assert.equal(playbackTime, 25);
playbackTime = 2;
api.ytSeekRelative(-5);
assert.equal(playbackTime, 0);
playbackTime = 58;
api.ytSeekRelative(5);
assert.equal(playbackTime, 60);
duration = 0;
api.ytSeekRelative(5);
assert.equal(playbackTime, 65, 'Unknown duration does not reset playback');
context.player = null;
assert.doesNotThrow(() => api.ytSeekRelative(5));
console.log('Keyboard seek regression checks passed');
