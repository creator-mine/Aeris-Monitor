'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-panel-disabled-'));

// No PANEL_PASSWORD on purpose: the panel must refuse to authenticate.
process.env.PANEL_PASSWORD = '';
process.env.REGISTER_TOKEN = 'panel-api-token';
process.env.SETTINGS_FILE = path.join(tmp, 'settings.json');
process.env.REGISTRY_FILE = path.join(tmp, 'devices.json');
process.env.ALERTS_FILE = path.join(tmp, 'alerts.json');
process.env.RULES_FILE = path.join(tmp, 'rules.json');
process.env.STABILITY_FILE = path.join(tmp, 'stability.json');
process.env.METRICS_FILE = path.join(tmp, 'metrics.json');

const { createServer } = require('../src/app');

let server;
let base;

before(async () => {
  server = createServer();
  assert.equal(server.settings.panelEnabled(), false, 'panel must start disabled');
  await new Promise((resolve) => server.server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.server.address().port}`;
});

after(() => {
  server.server.close();
});

async function call(method, p, { body, token } = {}) {
  const headers = {};
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(base + p, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    /* not json */
  }
  return { status: res.status, json, text, headers: res.headers };
}

test('login reports the panel as disabled', async () => {
  const r = await call('POST', '/panel/api/auth/login', { body: { password: 'anything' } });
  assert.equal(r.status, 503);
  assert.equal(r.json.error, 'panel_disabled');
});

test('session endpoints report the panel as disabled', async () => {
  for (const p of ['/panel/api/auth/session', '/panel/api/session']) {
    const r = await call('GET', p);
    assert.equal(r.status, 503, `${p} must be disabled`);
    assert.equal(r.json.error, 'panel_disabled');
  }
});

test('a stray cookie does not unlock the panel api', async () => {
  const res = await fetch(base + '/panel/api/system', {
    headers: { Cookie: 'iot_panel=whatever' },
  });
  assert.equal(res.status, 401);
  assert.equal((await res.json()).error, 'unauthorized');
});

test('admin api still works for the api token holder', async () => {
  const anon = await call('GET', '/panel/api/system');
  assert.equal(anon.status, 401);

  const token = await call('GET', '/panel/api/system', { token: 'panel-api-token' });
  assert.equal(token.status, 200);
  assert.equal(token.json.ok, true);

  const devices = await call('GET', '/panel/api/devices', { token: 'panel-api-token' });
  assert.equal(devices.status, 200);
  assert.ok(Array.isArray(devices.json));

  const wrong = await call('GET', '/panel/api/system', { token: 'wrong-token' });
  assert.equal(wrong.status, 401);
});

test('unknown panel api routes are 401 without credentials', async () => {
  const r = await call('GET', '/panel/api/nope');
  assert.equal(r.status, 401);
  assert.equal(r.json.error, 'unauthorized');
});

test('the static shell is still served while the panel is disabled', async () => {
  const res = await fetch(base + '/panel/');
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type'), /text\/html/);
  assert.match(await res.text(), /<div id="app">/);
});

test('the redirect to /panel/ still works', async () => {
  const res = await fetch(base + '/panel', { redirect: 'manual' });
  assert.equal(res.status, 301);
  assert.equal(res.headers.get('location'), '/panel/');
});

test('health and meta stay public', async () => {
  const health = await call('GET', '/api/v1/health');
  assert.equal(health.status, 200);
  assert.equal(health.json.ok, true);

  const meta = await call('GET', '/api/v1/meta');
  assert.equal(meta.status, 200);
  assert.equal(meta.json.auth_enabled, true, 'api token is configured');
});
