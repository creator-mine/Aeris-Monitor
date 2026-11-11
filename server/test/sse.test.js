'use strict';

process.env.REGISTER_TOKEN = 'sse-test-token'; // enables the admin read requirement

const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');
const { EventEmitter } = require('node:events');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-sse-'));
process.env.SETTINGS_FILE = path.join(tmp, 'settings.json');
process.env.METRICS_FILE = path.join(tmp, 'metrics.json');
process.env.STABILITY_FILE = path.join(tmp, 'stability.json');
process.env.REGISTRY_FILE = path.join(tmp, 'registry.json');

const { TelemetryStore } = require('../src/ingest');
const { createServer } = require('../src/app');

function waitFor(fn, timeoutMs = 2000) {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const tick = () => {
      const v = fn();
      if (v) return resolve(v);
      if (Date.now() - start > timeoutMs) return reject(new Error('timeout waiting for condition'));
      setTimeout(tick, 20);
    };
    tick();
  });
}

function startApp() {
  const dataDir = path.join(tmp, `ingest-${Math.random().toString(36).slice(2)}`);
  const telemetry = new TelemetryStore({ dir: dataDir, latestFile: path.join(dataDir, 'latest.json') });
  const mqtt = new EventEmitter();
  mqtt.published = [];
  mqtt.publish = (topic, payload) => {
    mqtt.published.push({ topic, payload });
    return true;
  };
  const app = createServer({ telemetry, mqtt });
  return new Promise((resolve) => {
    app.server.listen(0, '127.0.0.1', () => resolve({ app, telemetry, mqtt, base: `http://127.0.0.1:${app.server.address().port}` }));
  });
}

function collect(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = [];
    const req = http.get(url, { headers }, (res) => {
      const { statusCode, headers: h } = res;
      res.on('data', (c) => data.push(c.toString()));
      res.on('end', () => resolve({ status: statusCode, headers: h, body: data.join('') }));
    });
    req.on('error', reject);
  });
}

const TOKEN = { Authorization: 'Bearer sse-test-token' };

function teardownApp(app, telemetry) {
  telemetry.close();
  app.server.closeAllConnections?.();
  app.server.close();
}

test('stream requires admin auth and broadcasts live metrics', async () => {
  const { app, telemetry, mqtt, base } = await startApp();
  try {
    // Without a token the stream is rejected (REGISTER_TOKEN is set above).
    assert.equal((await collect(base + '/api/v1/stream')).status, 401);

    const liveBuf = [];
    let streamType = null;
    let streamStatus = 0;
    const req = http.get(base + '/api/v1/stream', { headers: TOKEN }, (r) => {
      streamStatus = r.statusCode;
      streamType = r.headers['content-type'];
      r.on('data', (c) => liveBuf.push(c.toString()));
    });
    req.on('error', () => {});

    await waitFor(() => (liveBuf.join('').includes('event: hello')));
    assert.equal(streamStatus, 200);
    assert.ok(String(streamType).includes('text/event-stream'));
    assert.ok(liveBuf.join('').includes('event: hello'), 'hello frame with a snapshot');

    mqtt.emit('metric', { deviceId: 'd1', sensor: 'temp', t: 1720000000000, v: 42.5, u: 'degC' });
    mqtt.emit('status', { deviceId: 'd1', status: 'online', uptime: 99 });

    await waitFor(() => {
      const s = liveBuf.join('');
      return s.includes('event: metric') && s.includes('42.5') && s.includes('event: status');
    });

    const frames = liveBuf.join('').split('event: ');
    assert.ok(frames.some((f) => f.startsWith('metric')), 'metric frame received');
    assert.ok(frames.some((f) => f.startsWith('status')), 'status frame received');
  } finally {
    teardownApp(app, telemetry);
  }
});

test('sensors/latest requires admin auth and reflects appended samples', async () => {
  const { app, telemetry, base } = await startApp();
  try {
    assert.equal((await collect(base + '/api/v1/sensors/latest')).status, 401);

    const empty = await collect(base + '/api/v1/sensors/latest', TOKEN);
    assert.equal(empty.status, 200);
    assert.deepEqual(JSON.parse(empty.body).devices, {});

    telemetry.append({ deviceId: 'd1', sensor: 'temp', timestamp: 1720000000000, value: 23.4, unit: 'degC' });
    const full = await collect(base + '/api/v1/sensors/latest', TOKEN);
    const body = JSON.parse(full.body);
    assert.deepEqual(body.devices.d1.temp, { t: 1720000000000, v: 23.4, u: 'degC' });
  } finally {
    teardownApp(app, telemetry);
  }
});

test('sensor history endpoint requires admin auth and returns the time series', async () => {
  const { app, telemetry, base } = await startApp();
  try {
    const url = base + '/api/v1/sensors/d1/temp/history?from=1719990000000&to=1720010000000';
    assert.equal((await collect(url)).status, 401);

    const noData = await collect(url, TOKEN);
    assert.equal(noData.status, 200);
    assert.deepEqual(JSON.parse(noData.body).series, []);

    telemetry.append({ deviceId: 'd1', sensor: 'temp', timestamp: 1720000000000, value: 21.5, unit: 'degC' });
    telemetry.append({ deviceId: 'd1', sensor: 'temp', timestamp: 1720000001000, value: 22.5, unit: 'degC' });

    const data = JSON.parse((await collect(url, TOKEN)).body);
    assert.equal(data.deviceId, 'd1');
    assert.equal(data.sensor, 'temp');
    assert.equal(data.series.length, 2);
    assert.deepEqual(data.series.map((p) => p.v), [21.5, 22.5]);
    assert.equal(data.series[0].u, 'degC');

    const withPoints = JSON.parse(
      (await collect(base + '/api/v1/sensors/d1/temp/history?points=8&from=1719990000000&to=1720010000000', TOKEN)).body,
    );
    assert.equal(withPoints.series.length, 2);

    const badRange = JSON.parse(
      (await collect(base + '/api/v1/sensors/d1/temp/history?from=1720010000000&to=1719990000000', TOKEN)).body,
    );
    assert.equal(badRange.series.length, 0);
  } finally {
    teardownApp(app, telemetry);
  }
});

test('history filters by sensor name and validates references', async () => {
  const { app, telemetry, base } = await startApp();
  try {
    telemetry.append({ deviceId: 'd1', sensor: 'temp', timestamp: 1720000000000, value: 18 });
    telemetry.append({ deviceId: 'd1', sensor: 'bmp', timestamp: 1720000000000, value: 1013 });
    telemetry.append({ deviceId: 'safer', sensor: 'temp', timestamp: 1720000000000, value: 7 });

    const other = JSON.parse(
      (await collect(base + '/api/v1/sensors/d1/bmp/history?from=1719990000000&to=1720010000000', TOKEN)).body,
    );
    assert.equal(other.series.length, 1);
    assert.equal(other.series[0].v, 1013);

    const unknown = JSON.parse(
      (await collect(base + '/api/v1/sensors/nope/temp/history?from=1719990000000&to=1720010000000', TOKEN)).body,
    );
    assert.equal(unknown.series.length, 0);
  } finally {
    teardownApp(app, telemetry);
  }
});

function postJson(url, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = http.request(
      url,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data), ...headers },
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c.toString()));
        res.on('end', () => resolve({ status: res.statusCode, body: chunks.join('') }));
      },
    );
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

test('device command endpoint publishes to iot/<device>/commands and requires auth', async () => {
  const { app, telemetry, mqtt, base } = await startApp();
  try {
    const denied = await postJson(base + '/api/v1/devices/d1/command', { command: 'relay:on' });
    assert.equal(denied.status, 401);

    const badId = await postJson(base + '/api/v1/devices/a%20b/command', { command: 'x' }, TOKEN);
    assert.equal(badId.status, 400);

    const ok = await postJson(base + '/api/v1/devices/d1/command', { command: 'relay:on' }, TOKEN);
    assert.equal(ok.status, 200);
    const parsed = JSON.parse(ok.body);
    assert.equal(parsed.ok, true);

    assert.equal(mqtt.published.length, 1);
    assert.deepEqual(mqtt.published[0], { topic: 'iot/d1/commands', payload: 'relay:on' });

    const missing = await postJson(base + '/api/v1/devices/d1/command', {}, TOKEN);
    assert.equal(missing.status, 400);
  } finally {
    teardownApp(app, telemetry);
  }
});