'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-settings-'));

process.env.SETTINGS_FILE = path.join(tmp, 'settings.json');

const config = require('../src/config');
const { SettingsStore } = require('../src/settings');

function store(name) {
  process.env.SETTINGS_FILE = path.join(tmp, name);
  return new SettingsStore();
}

test('falls back to env-derived config when nothing is overridden', () => {
  const s = store('fallback.json');
  assert.equal(s.staleMs(), config.registry.staleMs);
  assert.equal(s.metricsHours(), config.metrics.hours);
  assert.equal(s.sessionTtlMs(), config.panel.sessionTtlMs);
  assert.equal(s.maxDevicesPerIp(), config.registry.maxDevicesPerIp);
  assert.equal(s.rateLimit('window_ms'), config.rateLimit.windowMs);
  assert.equal(s.rateLimit('register'), config.rateLimit.register);
  assert.equal(s.rateLimit('heartbeat'), config.rateLimit.heartbeat);
  assert.equal(s.rateLimit('write'), config.rateLimit.write);
  assert.equal(s.rateLimit('read'), config.rateLimit.read);
  assert.equal(s.rateLimit('unknown_limit'), undefined);
  assert.equal(s.panelPassword(), '');
  assert.equal(s.panelEnabled(), false);
  assert.equal(s.get('no_such_key'), undefined);
});

test('numeric overrides are applied and persisted', () => {
  const s = store('numeric.json');
  const r = s.update({ stale_ms: 5000, metrics_hours: 6 });
  assert.deepEqual(r, { ok: true, applied: ['stale_ms', 'metrics_hours'] });
  assert.equal(s.staleMs(), 5000);
  assert.equal(s.metricsHours(), 6);

  const reloaded = new SettingsStore(); // same file
  assert.equal(reloaded.staleMs(), 5000);
  assert.equal(reloaded.metricsHours(), 6);
});

test('out-of-range and non-integer numbers are rejected', () => {
  const s = store('reject.json');
  assert.deepEqual(s.update(null), { ok: false, error: 'invalid_payload' });
  assert.deepEqual(s.update('stale_ms=5000'), { ok: false, error: 'invalid_payload' });
  assert.deepEqual(s.update(undefined), { ok: false, error: 'invalid_payload' });
  assert.deepEqual(s.update({}), { ok: true, applied: [] });

  assert.deepEqual(s.update({ stale_ms: 999 }), { ok: false, error: 'invalid_stale_ms' });
  assert.deepEqual(s.update({ stale_ms: 86400 * 7 * 1000 + 1 }), { ok: false, error: 'invalid_stale_ms' });
  assert.deepEqual(s.update({ stale_ms: 1.5 }), { ok: false, error: 'invalid_stale_ms' });
  assert.deepEqual(s.update({ stale_ms: 'abc' }), { ok: false, error: 'invalid_stale_ms' });
  assert.deepEqual(s.update({ metrics_hours: 0 }), { ok: false, error: 'invalid_metrics_hours' });
  assert.deepEqual(s.update({ metrics_hours: 24 * 30 + 1 }), { ok: false, error: 'invalid_metrics_hours' });
  assert.deepEqual(s.update({ session_ttl_ms: 1000 }), { ok: false, error: 'invalid_session_ttl_ms' });
  assert.deepEqual(s.update({ max_devices_per_ip: -1 }), { ok: false, error: 'invalid_max_devices_per_ip' });
  assert.deepEqual(s.update({ max_devices_per_ip: 1.5 }), { ok: false, error: 'invalid_max_devices_per_ip' });
});

test('a rejected update never mutates or persists the store', () => {
  const s = store('atomic.json');
  assert.equal(s.update({ stale_ms: 5000 }).ok, true);
  assert.equal(s.update({ stale_ms: 1 }).ok, false);
  assert.equal(s.staleMs(), 5000);
  assert.equal(new SettingsStore().staleMs(), 5000);
});

test('rate limit overrides merge with existing ones', () => {
  const s = store('rates.json');
  assert.deepEqual(s.update({ rate_limits: { register: 5 } }), { ok: true, applied: ['rate_limits'] });
  assert.equal(s.rateLimit('register'), 5);
  assert.equal(s.rateLimit('read'), config.rateLimit.read);

  assert.deepEqual(s.update({ rate_limits: { heartbeat: 100 } }), { ok: true, applied: ['rate_limits'] });
  assert.equal(s.rateLimit('heartbeat'), 100);
  assert.equal(s.rateLimit('register'), 5, 'earlier override must survive');

  assert.deepEqual(s.update({ rate_limits: { register: 0 } }), { ok: false, error: 'invalid_rate_limit_register' });
  assert.deepEqual(s.update({ rate_limits: { window_ms: 'nope' } }), {
    ok: false,
    error: 'invalid_rate_limit_window_ms',
  });
  assert.deepEqual(s.update({ rate_limits: null }), { ok: false, error: 'invalid_rate_limits' });
  assert.equal(s.rateLimit('register'), 5, 'failed update must not clobber the store');

  // Unknown names inside a valid object are ignored, not rejected.
  assert.deepEqual(s.update({ rate_limits: { made_up: 7 } }), { ok: true, applied: ['rate_limits'] });
  assert.equal(s.rateLimit('made_up'), undefined);
});

test('session_ttl alias is normalized to session_ttl_ms', () => {
  const s = store('ttl.json');
  assert.deepEqual(s.update({ session_ttl: 3600 * 1000 }), { ok: true, applied: ['session_ttl_ms'] });
  assert.equal(s.sessionTtlMs(), 3600 * 1000);
  assert.equal(s.get('session_ttl'), undefined);
  assert.equal(s.get('session_ttl_ms'), 3600 * 1000);
});

test('max_devices_per_ip accepts zero', () => {
  const s = store('max-dev.json');
  assert.deepEqual(s.update({ max_devices_per_ip: 0 }), { ok: true, applied: ['max_devices_per_ip'] });
  assert.equal(s.maxDevicesPerIp(), 0);
  assert.equal(new SettingsStore().maxDevicesPerIp(), 0);
});

test('panel_password is length-checked and enables the panel', () => {
  const s = store('panel-pass.json');
  assert.equal(s.panelEnabled(), false);
  assert.deepEqual(s.update({ panel_password: '' }), { ok: false, error: 'invalid_panel_password' });
  assert.deepEqual(s.update({ panel_password: 'short' }), { ok: false, error: 'invalid_panel_password' });
  assert.deepEqual(s.update({ panel_password: 'x'.repeat(129) }), { ok: false, error: 'invalid_panel_password' });
  assert.equal(s.panelEnabled(), false);

  assert.deepEqual(s.update({ panel_password: 'good-password-1' }), {
    ok: true,
    applied: ['panel_password'],
  });
  assert.equal(s.panelPassword(), 'good-password-1');
  assert.equal(s.panelEnabled(), true);

  const reloaded = new SettingsStore(); // same file
  assert.equal(reloaded.panelEnabled(), true);
  assert.equal(reloaded.panelPassword(), 'good-password-1');
});

test('a corrupted settings file falls back to an empty override set', () => {
  process.env.SETTINGS_FILE = path.join(tmp, 'corrupt.json');
  fs.writeFileSync(process.env.SETTINGS_FILE, '{ not json');
  const s = new SettingsStore();
  assert.deepEqual(s.overrides, {});
  assert.equal(s.staleMs(), config.registry.staleMs);
});
