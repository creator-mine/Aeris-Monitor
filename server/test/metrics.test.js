'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const { MetricsCollector, downsample } = require('../src/metrics');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-metrics-'));

function collector(name, opts = {}) {
  return new MetricsCollector({ file: path.join(tmp, name), hours: 24, ...opts });
}

test('downsample returns [] for an empty series', () => {
  assert.deepEqual(downsample([], 10), []);
});

test('downsample copies a series shorter than the requested points', () => {
  const samples = [{ t: 1, cpu: 5 }, { t: 2, cpu: 7 }];
  const out = downsample(samples, 10);
  assert.equal(out.length, 2);
  assert.deepEqual(out[0], { t: 1, cpu: 5 });
  assert.notEqual(out[0], samples[0]);
});

test('downsample averages buckets and takes t from the first sample', () => {
  const samples = Array.from({ length: 10 }, (_, i) => ({ t: 1000 + i, cpu: i, mem: 2 }));
  const out = downsample(samples, 5);
  assert.equal(out.length, 5);
  assert.equal(out[0].cpu, 0.5);
  assert.equal(out[0].t, 1000);
  assert.equal(out[4].cpu, 8.5);
  assert.equal(out[4].t, 1008);
  assert.ok(out.every((s) => s.mem === 2));
});

test('downsample skips null fields while averaging', () => {
  const out = downsample(
    [
      { t: 1, cpu: 10, net_rx_kb_s: null },
      { t: 2, cpu: 20, net_rx_kb_s: null },
      { t: 3, cpu: 30, net_rx_kb_s: 5 },
      { t: 4, cpu: 40, net_rx_kb_s: 15 },
    ],
    2,
  );
  assert.equal(out.length, 2);
  assert.equal(out[0].cpu, 15);
  assert.equal(out[0].t, 1);
  assert.ok(!('net_rx_kb_s' in out[0]), 'a bucket without any value drops the key');
  assert.equal(out[1].cpu, 35);
  assert.equal(out[1].net_rx_kb_s, 10);
  assert.equal(out[1].t, 3);
});

test('sample records a well-formed point', () => {
  const m = collector('shape.json');
  assert.equal(m.last(), null);

  m.sample(null);
  assert.equal(m.samples.length, 1);

  const s = m.last();
  assert.ok(Number.isFinite(s.t));
  assert.ok(s.cpu >= 0 && s.cpu <= 100);
  assert.ok(s.mem >= 0 && s.mem <= 100);
  assert.ok(s.load1 === null || s.load1 >= 0);
  assert.equal(s.online, 0);
  assert.equal(s.offline, 0);
  assert.equal(s.req_min, 0);
  assert.equal(s.avg_ms, 0);
});

test('sample consumes request counters and device stats', () => {
  const m = collector('stats.json');
  const stats = {
    requests: { count: 10, sumMs: 123 },
    devices: () => ({ total: 3, online: 2, offline: 1 }),
  };

  m.sample(stats);
  const s = m.last();
  assert.equal(s.online, 2);
  assert.equal(s.offline, 1);
  assert.equal(s.avg_ms, 12.3);
  assert.equal(stats.requests.count, 0);
  assert.equal(stats.requests.sumMs, 0);

  m.sample(stats);
  assert.equal(m.last().avg_ms, 0);
});

test('history clamps the point count and mirrors samples online', () => {
  const m = collector('history.json');
  for (let i = 0; i < 5; i++) m.sample(null);

  const h = m.history();
  assert.equal(h.perf.length, 5);
  assert.equal(h.online.length, 5);
  assert.deepEqual(Object.keys(h.perf[0]).sort(), [
    'avg_ms',
    'cpu',
    'load1',
    'mem',
    'net_rx_kb_s',
    'net_tx_kb_s',
    'req_min',
    't',
  ]);
  assert.deepEqual(Object.keys(h.online[0]).sort(), ['offline', 'online', 't']);
  assert.equal(h.perf[4].t, h.online[4].t);

  assert.equal(m.history(100_000).perf.length, 5);
  assert.equal(m.history(1).perf.length, 2);
  assert.equal(m.history('abc').perf.length, 5);
  assert.equal(m.history(-5).perf.length, 2);
});

test('flush persists samples and a new collector reloads them', () => {
  const file = path.join(tmp, 'persist.json');
  const a = new MetricsCollector({ file, hours: 24 });
  a.sample(null);
  a.sample(null);
  a.flush();

  const b = new MetricsCollector({ file, hours: 24 });
  assert.equal(b.samples.length, 2);
  assert.equal(b.last().t, a.last().t);
});

test('samples outside the retention window are dropped on load', () => {
  const file = path.join(tmp, 'trim.json');
  const a = new MetricsCollector({ file, hours: 24 });
  const now = Date.now();
  a.samples.push({ t: now - 48 * 3600 * 1000, cpu: 1 });
  a.samples.push({ t: now - 3600 * 1000, cpu: 2 });
  a.samples.push({ t: now, cpu: 3 });
  a.flush();

  const b = new MetricsCollector({ file, hours: 24 });
  assert.equal(b.samples.length, 2);
  assert.equal(b.samples[0].cpu, 2);
  assert.equal(b.last().cpu, 3);
});

test('start/stop manage the sampling timer', () => {
  const m = collector('timer.json', { intervalMs: 50 });
  m.start({ requests: { count: 0, sumMs: 0 }, devices: () => ({ total: 0, online: 0, offline: 0 }) });
  assert.notEqual(m.timer, null);
  m.start({ requests: { count: 0, sumMs: 0 } }); // idempotent
  assert.equal(m.samples.length, 0);
  m.stop();
  assert.equal(m.timer, null);
});
