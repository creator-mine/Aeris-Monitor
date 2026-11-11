'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-panel-'));

const PANEL_PASSWORD = 'panel-secret-123';
const API_TOKEN = 'panel-api-token';

process.env.PANEL_PASSWORD = PANEL_PASSWORD;
process.env.REGISTER_TOKEN = API_TOKEN;
process.env.SETTINGS_FILE = path.join(tmp, 'settings.json');
process.env.REGISTRY_FILE = path.join(tmp, 'devices.json');
process.env.ALERTS_FILE = path.join(tmp, 'alerts.json');
process.env.RULES_FILE = path.join(tmp, 'rules.json');
process.env.STABILITY_FILE = path.join(tmp, 'stability.json');
process.env.METRICS_FILE = path.join(tmp, 'metrics.json');

const { createServer } = require('../src/app');
const { COOKIE } = require('../src/session');
const VERSION = require('../package.json').version;

let server;
let base;
let sessionCookie;

before(async () => {
  server = createServer();
  const seeded = server.registry.register({
    id: 'seed-dev',
    name: 'seed device',
    type: 'esp32-c3',
    ip: '10.0.0.50',
    port: 80,
    sensors: ['temp'],
  });
  assert.ok(seeded, 'seed device must register');
  await new Promise((resolve) => server.server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.server.address().port}`;
  // One session for the whole file: logins share a 5/min rate-limit bucket.
  sessionCookie = await login();
});

after(() => {
  server.server.close();
});

async function call(instance, method, p, { body, cookie, token, raw = false, redirect } = {}) {
  const headers = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (cookie) headers.Cookie = cookie;
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(instance + p, {
    method,
    headers,
    redirect,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (raw) return res;
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    /* not json */
  }
  return { status: res.status, json, text, headers: res.headers };
}

const get = (p, opts) => call(base, 'GET', p, opts);
const post = (p, body, opts = {}) => call(base, 'POST', p, { ...opts, body });

test('GET /panel redirects to /panel/', async () => {
  const r = await call(base, 'GET', '/panel', { redirect: 'manual' });
  assert.equal(r.status, 301);
  assert.equal(r.headers.get('location'), '/panel/');
});

test('GET /panel/ serves the panel shell', async () => {
  const res = await get('/panel/', { raw: true });
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /text\/html/);
  const html = await res.text();
  assert.match(html, /<div id="app">/);
  assert.match(html, /IoT Panel/);
});

test('panel assets are served with immutable caching', async () => {
  const shell = await get('/panel/', { raw: true });
  const html = await shell.text();
  const asset = html.match(/src="(\/panel\/assets\/[^"]+\.js)"/);
  assert.ok(asset, 'the shell must reference a bundled script');

  const res = await get(asset[1], { raw: true });
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /javascript/);
  assert.match(res.headers.get('cache-control'), /max-age=31536000/);
});

test('panel api rejects anonymous requests', async () => {
  for (const p of [
    '/panel/api/auth/session',
    '/panel/api/system',
    '/panel/api/system/history',
    '/panel/api/devices',
    '/panel/api/settings',
  ]) {
    const r = await get(p);
    assert.equal(r.status, 401, `${p} must require auth`);
    assert.equal(r.json.error, 'unauthorized');
  }
});

test('login rejects the wrong password', async () => {
  const r = await post('/panel/api/auth/login', { password: 'nope' });
  assert.equal(r.status, 401);
  assert.equal(r.json.error, 'unauthorized');
});

test('login with the right password issues a session cookie', async () => {
  const r = await post('/panel/api/auth/login', { password: PANEL_PASSWORD });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { ok: true });

  const setCookie = r.headers.get('set-cookie');
  assert.match(setCookie, new RegExp(`^${COOKIE}=`));
  assert.match(setCookie, /HttpOnly/);
  assert.match(setCookie, /Path=\//);
  assert.match(setCookie, /SameSite=Lax/);
  assert.match(setCookie, /Max-Age=\d+/);
});

async function login() {
  const r = await post('/panel/api/auth/login', { password: PANEL_PASSWORD });
  assert.equal(r.status, 200);
  return r.headers.get('set-cookie').split(';')[0];
}

test('the session endpoint answers for a logged-in client', async () => {
  const cookie = sessionCookie;
  const r = await get('/panel/api/auth/session', { cookie });
  assert.equal(r.status, 200);
  assert.equal(r.json.ok, true);
  assert.equal(r.json.version, VERSION);
  assert.equal(r.json.path, '/panel');
  assert.equal(r.json.panel_enabled, true);
  assert.equal(r.json.api_token_set, true);
});

test('the session alias /panel/api/session behaves the same', async () => {
  const cookie = sessionCookie;
  const withSession = await get('/panel/api/session', { cookie });
  assert.equal(withSession.status, 200);
  assert.equal(withSession.json.ok, true);

  const anonymous = await get('/panel/api/session');
  assert.equal(anonymous.status, 401);
});

test('system, devices and settings are readable with a session', async () => {
  const cookie = sessionCookie;

  const sys = await get('/panel/api/system', { cookie });
  assert.equal(sys.status, 200);
  assert.equal(sys.json.ok, true);
  assert.equal(sys.json.version, VERSION);
  assert.ok(sys.json.devices, 'device stats present');
  assert.deepEqual(sys.json.alerts, { total: 0, active: 0 });
  assert.deepEqual(sys.json.rules, { total: 0, enabled: 0 });
  assert.equal(typeof sys.json.metrics_window_hours, 'number');
  assert.ok('cpu_percent' in sys.json);
  assert.ok('mem_percent' in sys.json);

  const hist = await get('/panel/api/system/history?points=5', { cookie });
  assert.equal(hist.status, 200);
  assert.equal(hist.json.timestamps.length, hist.json.metrics.cpu.length);
  assert.ok(hist.json.metrics.cpu.length >= 0);

  const devices = await get('/panel/api/devices', { cookie });
  assert.equal(devices.status, 200);
  assert.ok(Array.isArray(devices.json), 'the panel device list is a bare array');
  assert.equal(devices.json.length, 1); // only the seeded device so far
  assert.equal(devices.json[0].id, 'seed-dev');
  assert.equal(devices.json[0].uptime24, 100, 'seeded online during this run');
  assert.ok('alerts' in devices.json[0]);
});

test('settings never echo secrets', async () => {
  const cookie = sessionCookie;
  const r = await get('/panel/api/settings', { cookie });
  assert.equal(r.status, 200);
  assert.equal(r.json.panel.enabled, true);
  assert.equal(r.json.api_token_set, true);
  assert.equal(r.json.panel.path, '/panel');
  assert.equal(r.json.api_prefix, '/api/v1');

  const raw = JSON.stringify(r.json);
  assert.ok(!raw.includes(PANEL_PASSWORD), 'panel password must not be echoed');
  assert.ok(!raw.includes(API_TOKEN), 'api token must not be echoed');
  assert.ok(!('api_token' in r.json));
  assert.ok(!('panel_password' in r.json));
});

test('api token grants admin access, but never a session', async () => {
  const withToken = await get('/panel/api/system', { token: API_TOKEN });
  assert.equal(withToken.status, 200);
  assert.equal(withToken.json.ok, true);

  const sessionViaToken = await get('/panel/api/auth/session', { token: API_TOKEN });
  assert.equal(sessionViaToken.status, 401, 'session endpoint demands a real cookie');
});

test('devices can be edited through the panel api', async () => {
  const cookie = sessionCookie;

  const created = await post('/panel/api/devices', {
    id: 'panel-dev',
    name: 'panel device',
    ip: '10.1.1.1',
    port: 8080,
    sensors: ['temp'],
  }, { cookie });
  assert.equal(created.status, 200);
  assert.equal(created.json.ok, true);

  const list = await get('/panel/api/devices', { cookie });
  assert.equal(list.json.length, 2);

  const updated = await call(base, 'PUT', '/panel/api/devices/panel-dev', {
    cookie,
    body: { name: 'renamed', port: 9090 },
  });
  assert.equal(updated.status, 200);
  assert.equal(updated.json.device.name, 'renamed');
  assert.equal(updated.json.device.port, 9090);

  const bad = await call(base, 'PUT', '/panel/api/devices/panel-dev', {
    cookie,
    body: { ip: 'not an ip' },
  });
  assert.equal(bad.status, 400);
  assert.equal(bad.json.error, 'invalid_device');

  const missing = await call(base, 'PUT', '/panel/api/devices/ghost', {
    cookie,
    body: { name: 'x' },
  });
  assert.equal(missing.status, 404);

  const removed = await call(base, 'DELETE', '/panel/api/devices/panel-dev', { cookie });
  assert.equal(removed.status, 200);
  assert.equal((await get('/panel/api/devices', { cookie })).json.length, 1);
});

test('logout clears the session cookie', async () => {
  const cookie = sessionCookie;
  const r = await post('/panel/api/auth/logout', undefined, { cookie });
  assert.equal(r.status, 200);
  assert.match(r.headers.get('set-cookie'), /Max-Age=0/);
});

test('unknown panel api routes are 404 for authorized users', async () => {
  const cookie = sessionCookie;
  const r = await get('/panel/api/nope', { cookie });
  assert.equal(r.status, 404);
  assert.equal(r.json.error, 'not_found');
});

test('login is rate limited after 5 attempts', async () => {
  // Fresh server instance => fresh rate-limit buckets.
  const fresh = createServer().server;
  await new Promise((resolve) => fresh.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${fresh.address().port}`;

  const attempts = [];
  for (let i = 0; i < 6; i++) {
    attempts.push(
      await call(url, 'POST', '/panel/api/auth/login', { body: { password: `wrong-${i}` } }),
    );
  }
  fresh.close();

  assert.deepEqual(
    attempts.map((a) => a.status),
    [401, 401, 401, 401, 401, 429],
  );
  assert.equal(attempts[5].json.error, 'rate_limited');
});
