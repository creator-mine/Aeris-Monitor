'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const { TelemetryStore, hourOf, hourStart, safeComponent } = require('../src/ingest');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-ingest-'));

const H = (h, m = 0) => Date.UTC(2026, 9, 7, h, m, 0);

function store(name = 'store') {
  const dir = path.join(tmp, name);
  return new TelemetryStore({ dir, latestFile: path.join(dir, 'latest.json'), flushSeconds: 3600 });
}

function readLines(file) {
  try {
    return fs
      .readFileSync(file, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map((l) => JSON.parse(l));
  } catch {
    return [];
  }
}

test('append accepts a well-formed sample and exposes it', () => {
  const t = store('basic');
  const ok = t.append({ deviceId: 'esp32c3_001', sensor: 'temp', timestamp: H(14, 5), value: 22.5, unit: 'degC' });
  assert.equal(ok, true);

  assert.deepEqual(t.latestValues('esp32c3_001'), {
    temp: { t: H(14, 5), v: 22.5, u: 'degC' },
  });
  assert.deepEqual(t.stats(), { devices: 1, sensors: 1 });

  const series = t.query('esp32c3_001', 'temp', { from: H(13), to: H(15) });
  assert.equal(series.length, 1);
  assert.equal(series[0].v, 22.5);
  assert.equal(series[0].u, 'degC');
  t.close();
});

test('append rejects malformed samples silently', () => {
  const t = store('reject');
  assert.equal(t.append({ deviceId: 'bad/name', sensor: 'temp', timestamp: H(14), value: 1 }), false);
  assert.equal(t.append({ deviceId: 'dev', sensor: '..', timestamp: H(14), value: 1 }), false);
  assert.equal(t.append({ deviceId: 'dev', sensor: 'temp', timestamp: Number.NaN, value: 1 }), false);
  assert.equal(t.append({ deviceId: 'dev', sensor: 'temp', timestamp: H(14), value: Number.NaN }), false);
  assert.equal(t.append({ deviceId: 'dev', sensor: 'temp', timestamp: 0, value: 1 }), false);
  assert.equal(t.append(null), false);
  assert.deepEqual(t.stats(), { devices: 0, sensors: 0 });
  assert.equal(t.query('dev', 'temp', { from: H(13), to: H(15) }).length, 0);
  t.close();
});

test('samples are persisted as per-hour JSONL files', () => {
  const t = store('raw');
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 0), value: 20 });
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 30), value: 21 });
  t.append({ deviceId: 'dev1', sensor: 'hum', timestamp: H(14, 30), value: 55 });

  const lines = readLines(path.join(tmp, 'raw', 'raw', 'dev1', 'temp', '2026-10-07T14.jsonl'));
  assert.equal(lines.length, 2);
  assert.equal(lines[1].v, 21);
  t.close();
});

test('an hour change finalizes the rollup for the closed hour', () => {
  const t = store('rollup');
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 10), value: 20 });
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 20), value: 30 });
  assert.equal(t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(15, 5), value: 40 }), true);

  const rolls = readLines(path.join(tmp, 'rollup', 'rollup', 'dev1', 'temp.jsonl'));
  assert.equal(rolls.length, 1, 'the completed 14:00 hour must be summarized');
  const r = rolls[0];
  assert.equal(r.h, '2026-10-07T14');
  assert.equal(r.count, 2);
  assert.equal(r.min, 20);
  assert.equal(r.max, 30);
  assert.equal(r.sum, 50);
  assert.equal(r.avg, 25);
  assert.equal(r.first_v, 20);
  assert.equal(r.last_v, 30);

  const closed = fs.existsSync(path.join(tmp, 'rollup', 'raw', 'dev1', 'temp', '2026-10-07T14.jsonl'));
  assert.equal(closed, true, 'raw data for the closed hour is still on disk');
  t.close();
});

test('flush finalizes rolls for hours that ended without new traffic', () => {
  const t = store('flush');
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 0), value: 5 });
  t.flush();
  const rolls = readLines(path.join(tmp, 'flush', 'rollup', 'dev1', 'temp.jsonl'));
  assert.equal(rolls.length, 1, 'flush() must close a past-hour accumulator');
  assert.equal(rolls[0].h, '2026-10-07T14');
  t.close();
});

test('query filters by range and sorts ascending', () => {
  const t = store('query');
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 10), value: 1 });
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 30), value: 2 });
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 50), value: 3 });

  const window = t.query('dev1', 'temp', { from: H(14, 20), to: H(14, 45) });
  assert.deepEqual(window.map((p) => p.v), [2]);
  assert.equal(window[0].u, null, 'no unit was given');

  const outside = t.query('dev1', 'temp', { from: H(16), to: H(17) });
  assert.equal(outside.length, 0);

  const reversed = t.query('dev1', 'temp', { from: H(15), to: H(14) });
  assert.equal(reversed.length, 0);
  t.close();
});

test('query downsamples long series to the requested point count', () => {
  const t = store('downsample');
  const base = H(14, 0);
  for (let i = 0; i < 100; i++) {
    t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: base + i * 1000, value: i });
  }

  const all = t.query('dev1', 'temp', { from: H(14), to: H(15) });
  assert.equal(all.length, 100, 'fewer points than requested are returned intact');

  const sparse = t.query('dev1', 'temp', { from: H(14), to: H(15), points: 10 });
  assert.equal(sparse.length, 10);
  assert.ok(sparse[0].t < sparse[9].t, 'output stays sorted');
  t.close();
});

test('a fresh store restores the latest cache from latest.json', () => {
  const dir = path.join(tmp, 'latest-cache');
  const a = new TelemetryStore({ dir, latestFile: path.join(dir, 'latest.json') });
  a.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 0), value: 22.5, unit: 'degC' });
  a.flush();
  a.close();

  const b = new TelemetryStore({ dir, latestFile: path.join(dir, 'latest.json') });
  assert.deepEqual(b.latestValues('dev1'), { temp: { t: H(14, 0), v: 22.5, u: 'degC' } });
  b.close();
});

test('close() finalizes every open accumulator', () => {
  const t = store('close');
  t.append({ deviceId: 'dev1', sensor: 'temp', timestamp: H(14, 0), value: 9 });
  t.close();
  const rolls = readLines(path.join(tmp, 'close', 'rollup', 'dev1', 'temp.jsonl'));
  assert.equal(rolls.length, 1);
});

test('safeComponent guards file-system traversal', () => {
  assert.equal(safeComponent('esp32c3_001'), 'esp32c3_001');
  assert.equal(safeComponent('a/b'), null);
  assert.equal(safeComponent('../x'), null);
  assert.equal(safeComponent('..'), null);
  assert.equal(safeComponent(''), null);
  assert.equal(safeComponent(null), null);
  assert.equal(safeComponent('x'.repeat(65)), null);
  assert.equal(safeComponent('a b'), null);
});

test('hourOf/hourStart are UTC-anchored', () => {
  const t = Date.UTC(2026, 9, 7, 14, 42, 0);
  assert.equal(hourOf(t), '2026-10-07T14');
  assert.equal(hourStart(hourOf(t)), Date.UTC(2026, 9, 7, 14, 0, 0));
});