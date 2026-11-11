'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const { StabilityStore, MAX_EVENTS_DEFAULT, UP_WINDOW_24H, UP_WINDOW_7D } = require('../src/stability');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-stability-'));

function store(name, opts = {}) {
  return new StabilityStore({ file: path.join(tmp, name), ...opts });
}

test('exports expose the documented windows and defaults', () => {
  assert.equal(MAX_EVENTS_DEFAULT, 5000);
  assert.equal(UP_WINDOW_24H, 24 * 3600 * 1000);
  assert.equal(UP_WINDOW_7D, 7 * 24 * 3600 * 1000);
});

test('record only stores transitions', () => {
  const s = store('transitions.json');
  s.record('dev1', 'online');
  s.record('dev1', 'online');
  s.record('dev1', 'online');
  assert.equal(s.events('dev1').length, 1);

  s.record('dev1', 'offline');
  s.record('dev1', 'offline');
  s.record('dev1', 'online');
  assert.deepEqual(s.events('dev1').map((e) => e.s), ['online', 'offline', 'online']);
  for (const e of s.events('dev1')) assert.ok(Number.isFinite(e.t));
});

test('record normalizes unknown statuses to online', () => {
  const s = store('normalize.json');
  s.record('dev1', 'weird');
  assert.equal(s.events('dev1')[0].s, 'online');
  s.record('dev1', null);
  assert.equal(s.events('dev1')[1].s, 'online');
});

test('the journal is capped at half of maxEvents', () => {
  const s = store('cap.json', { maxEvents: 500 });
  for (let i = 0; i < 600; i++) s.record('dev', i % 2 ? 'offline' : 'online');
  assert.equal(s.events('dev').length, 250);

  const big = store('cap-big.json', { maxEvents: 10_000 });
  for (let i = 0; i < 600; i++) big.record('dev', i % 2 ? 'offline' : 'online');
  assert.equal(big.events('dev').length, 600);
});

test('ensureOnline seeds or repairs the baseline', () => {
  const s = store('ensure.json');
  s.ensureOnline('fresh');
  assert.deepEqual(s.events('fresh').map((e) => e.s), ['online']);

  s.ensureOnline('fresh');
  assert.equal(s.events('fresh').length, 1);

  s.record('fresh', 'offline');
  s.ensureOnline('fresh');
  assert.deepEqual(s.events('fresh').map((e) => e.s), ['online', 'offline', 'online']);
});

test('removeDevice drops the journal', () => {
  const s = store('remove.json');
  s.record('gone', 'online');
  assert.equal(s.events('gone').length, 1);
  s.removeDevice('gone');
  assert.deepEqual(s.events('gone'), []);
  s.removeDevice('never-existed'); // no throw
});

test('events() returns a defensive copy', () => {
  const s = store('copy.json');
  s.record('dev', 'online');
  s.events('dev').push({ t: 1, s: 'offline' });
  assert.equal(s.events('dev').length, 1);
});

test('uptimePct is 0 without events', () => {
  const s = store('empty-uptime.json');
  assert.equal(s.uptimePct('nobody', UP_WINDOW_24H, 'online'), 0);
  assert.equal(s.uptime24h('nobody', 'online'), 0);
  assert.equal(s.uptime7d('nobody', 'offline'), 0);
});

test('uptimePct counts an always-online device at 100%', () => {
  const s = store('up.json');
  s._data.dev = [{ t: Date.now() - 3600_000, s: 'online' }];
  const pct = s.uptimePct('dev', UP_WINDOW_24H, 'online');
  assert.ok(Math.abs(pct - 100) < 1, `expected ~100, got ${pct}`);
  assert.equal(s.uptime24h('dev', 'online'), pct);
  assert.equal(s.uptime7d('dev', 'online'), pct);
});

test('uptimePct is 0 when a device is offline now', () => {
  const s = store('down.json');
  s._data.dev = [{ t: Date.now() - 3600_000, s: 'online' }];
  assert.equal(s.uptimePct('dev', UP_WINDOW_24H, 'offline'), 0);
});

test('uptimePct measures the online share of the journal', () => {
  const s = store('share.json');
  const now = Date.now();
  // Fabricated journal: online for the first half of a 60s window, then offline.
  s._data.dev = [
    { t: now - 60_000, s: 'online' },
    { t: now - 30_000, s: 'offline' },
  ];
  const pct = s.uptimePct('dev', 60_000, 'offline');
  assert.ok(Math.abs(pct - 50) < 1, `expected ~50, got ${pct}`);
});

test('uptimePct clamps to the device lifetime', () => {
  const s = store('young.json');
  s._data.young = [{ t: Date.now() - 2 * 3600_000, s: 'online' }];
  // Present for 2h in a 7d window: judged by its own lifetime, not the window.
  const pct = s.uptime7d('young', 'online');
  assert.ok(Math.abs(pct - 100) < 1, `expected ~100, got ${pct}`);
  assert.ok(Math.abs(s.uptimePct('young', 4 * 3600_000, 'online') - 100) < 1);
});

test('flush persists the journal and reload restores it', () => {
  const file = path.join(tmp, 'persist.json');
  const a = new StabilityStore({ file });
  a.record('dev', 'online');
  a.record('dev', 'offline');
  a.flush();

  const b = new StabilityStore({ file });
  assert.deepEqual(b.events('dev').map((e) => e.s), ['online', 'offline']);
});

test('a corrupted file falls back to an empty journal', () => {
  const file = path.join(tmp, 'corrupt.json');
  fs.writeFileSync(file, 'not json at all');
  const s = new StabilityStore({ file });
  assert.deepEqual(s.events('dev'), []);
});
