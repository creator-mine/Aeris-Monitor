'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-api-'));

// The HTTP API reuses the MQTT logins (HTTP Basic): devices use the device
// account, apps and tooling use the app account.
process.env.MQTT_USER = 'app';
process.env.MQTT_PASSWORD = 'app-secret';
process.env.MQTT_DEVICE_USER = 'device';
process.env.MQTT_DEVICE_PASSWORD = 'device-secret';
process.env.REGISTRY_FILE = path.join(tmp, 'devices.json');
process.env.ALERTS_FILE = path.join(tmp, 'alerts.json');
process.env.RATE_LIMIT_REGISTER = '100';
process.env.RATE_LIMIT_WRITE = '100';
process.env.RATE_LIMIT_HEARTBEAT = '100';
process.env.MAX_DEVICES_PER_IP = '2';

const { createServer } = require('../src/app');

let server;
let base;
let closed = false;

before(async () => {
  server = createServer().server;
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  if (!closed) {
    closed = true;
    server.close();
  }
});

function basic(user, pass) {
  return 'Basic ' + Buffer.from(`${user}:${pass}`).toString('base64');
}

const APP_AUTH = basic('app', 'app-secret');
const DEVICE_AUTH = basic('device', 'device-secret');

async function req(method, p, { body, auth } = {}) {
  const headers = {};
  if (body) headers['Content-Type'] = 'application/json';
  if (auth) headers['Authorization'] = auth;
  const res = await fetch(base + p, { method, headers, body: body ? JSON.stringify(body) : undefined });
  let json = null;
  try {
    json = await res.json();
  } catch {
    /* non-json */
  }
  return { status: res.status, json, headers: res.headers };
}

test('root returns text banner', async () => {
  const res = await fetch(base + '/');
  assert.equal(res.status, 200);
  const text = await res.text();
  assert.match(text, /Aeris Monitor/);
});

test('OPTIONS returns CORS preflight 204', async () => {
  const res = await req('OPTIONS', '/api/v1/devices');
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('access-control-allow-origin'), '*');
});

test('health returns shapes', async () => {
  const r = await req('GET', '/api/v1/health');
  assert.equal(r.status, 200);
  assert.equal(r.json.ok, true);
  assert.equal(typeof r.json.devices.total, 'number');
  assert.equal(typeof r.json.alerts, 'number');
  assert.equal(typeof r.json.panel_session, 'boolean');
});

test('meta reports basic auth', async () => {
  const r = await req('GET', '/api/v1/meta');
  assert.equal(r.status, 200);
  assert.equal(r.json.auth_enabled, true);
  assert.equal(r.json.auth_mode, 'basic');
  assert.equal(r.json.rate_limits.register, 100);
  assert.equal(r.json.max_devices_per_ip, 2);
});

test('register without credentials is 401', async () => {
  const r = await req('POST', '/api/v1/devices/register', {
    body: { id: 'noauth', ip: '10.0.0.1' },
  });
  assert.equal(r.status, 401);
});

test('register rejects the app login (device credentials required)', async () => {
  const r = await req('POST', '/api/v1/devices/register', {
    body: { id: 'app_register', ip: '10.0.0.4' },
    auth: APP_AUTH,
  });
  assert.equal(r.status, 401);
});

test('register flow: valid, missing fields, invalid json', async () => {
  const ok = await req('POST', '/api/v1/devices/register', {
    body: { id: 'api_dev1', ip: '10.0.0.2', port: 81 },
    auth: DEVICE_AUTH,
  });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.device.status, 'online');

  const missingIp = await req('POST', '/api/v1/devices/register', {
    body: { id: 'api_dev2' },
    auth: DEVICE_AUTH,
  });
  assert.equal(missingIp.status, 400);

  const badJson = await req('POST', '/api/v1/devices/register', {
    body: 'not json',
    auth: DEVICE_AUTH,
  });
  assert.equal(badJson.status, 400);
});

test('register exceeds max devices per ip with 429', async () => {
  const r1 = await req('POST', '/api/v1/devices/register', {
    body: { id: 'ip_1', ip: '10.0.0.99' },
    auth: DEVICE_AUTH,
  });
  const r2 = await req('POST', '/api/v1/devices/register', {
    body: { id: 'ip_2', ip: '10.0.0.99' },
    auth: DEVICE_AUTH,
  });
  const r3 = await req('POST', '/api/v1/devices/register', {
    body: { id: 'ip_3', ip: '10.0.0.99' },
    auth: DEVICE_AUTH,
  });
  assert.equal(r1.status, 200);
  assert.equal(r2.status, 200);
  assert.equal(r3.status, 429);
});

test('list and get device require the app login', async () => {
  const noAuthList = await req('GET', '/api/v1/devices');
  assert.equal(noAuthList.status, 401);
  const noAuthGet = await req('GET', '/api/v1/devices/api_dev1');
  assert.equal(noAuthGet.status, 401);

  const list = await req('GET', '/api/v1/devices', { auth: APP_AUTH });
  assert.equal(list.status, 200);
  assert.ok(Array.isArray(list.json));
  assert.ok(list.json.some((d) => d.id === 'api_dev1'));
  const one = await req('GET', '/api/v1/devices/api_dev1', { auth: APP_AUTH });
  assert.equal(one.status, 200);
  assert.equal(one.json.id, 'api_dev1');
  const missing = await req('GET', '/api/v1/devices/nope', { auth: APP_AUTH });
  assert.equal(missing.status, 404);
});

test('heartbeat registered returns 200, unknown 404', async () => {
  const ok = await req('POST', '/api/v1/devices/heartbeat', {
    body: { id: 'api_dev1' },
    auth: DEVICE_AUTH,
  });
  assert.equal(ok.status, 200);
  const missing = await req('POST', '/api/v1/devices/heartbeat', {
    body: { id: 'ghost' },
    auth: DEVICE_AUTH,
  });
  assert.equal(missing.status, 404);
});

test('heartbeat without credentials is 401', async () => {
  const r = await req('POST', '/api/v1/devices/heartbeat', { body: { id: 'api_dev1' } });
  assert.equal(r.status, 401);
});

test('alerts: list, create needs the app login, update, delete', async () => {
  const noAuth = await req('POST', '/api/v1/alerts', {
    body: { device_id: 'api_dev1', sensor_type: 'bme680', type: 'above', threshold: 30 },
  });
  assert.equal(noAuth.status, 401);

  const created = await req('POST', '/api/v1/alerts', {
    body: { device_id: 'api_dev1', sensor_type: 'bme680', type: 'above', threshold: 30 },
    auth: APP_AUTH,
  });
  assert.equal(created.status, 200);
  const id = created.json.id;

  const bad = await req('POST', '/api/v1/alerts', {
    body: { device_id: 'api_dev1', sensor_type: 'bme680', type: 'nope', threshold: 30 },
    auth: APP_AUTH,
  });
  assert.equal(bad.status, 400);

  const list = await req('GET', '/api/v1/alerts?device_id=api_dev1', { auth: APP_AUTH });
  assert.equal(list.status, 200);
  assert.equal(list.json.length, 1);

  const updated = await req('PUT', `/api/v1/alerts/${id}`, {
    body: { threshold: 99 },
    auth: APP_AUTH,
  });
  assert.equal(updated.status, 200);
  assert.equal(updated.json.threshold, 99);

  const del = await req('DELETE', `/api/v1/alerts/${id}`, { auth: APP_AUTH });
  assert.equal(del.status, 200);
  const del2 = await req('DELETE', `/api/v1/alerts/${id}`, { auth: APP_AUTH });
  assert.equal(del2.status, 404);
});

test('delete device removes its alerts', async () => {
  await req('POST', '/api/v1/alerts', {
    body: { device_id: 'api_dev1', sensor_type: 'bme680', type: 'above', threshold: 1 },
    auth: APP_AUTH,
  });
  const del = await req('DELETE', '/api/v1/devices/api_dev1', { auth: APP_AUTH });
  assert.equal(del.status, 200);
  const list = await req('GET', '/api/v1/alerts?device_id=api_dev1', { auth: APP_AUTH });
  assert.equal(list.json.length, 0);
});

test('delete device without credentials is 401', async () => {
  const r = await req('DELETE', '/api/v1/devices/api_dev1');
  assert.equal(r.status, 401);
});

test('rules list requires the app login', async () => {
  assert.equal((await req('GET', '/api/v1/rules')).status, 401);
  const list = await req('GET', '/api/v1/rules', { auth: APP_AUTH });
  assert.equal(list.status, 200);
  assert.ok(Array.isArray(list.json));
});

test('unknown route is 404', async () => {
  const r = await req('GET', '/api/v1/whatever');
  assert.equal(r.status, 404);
});
