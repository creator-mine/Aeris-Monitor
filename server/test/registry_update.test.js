'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const fs = require('node:fs');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'iot-registry-update-'));

process.env.REGISTRY_FILE = path.join(tmp, 'devices.json');

const { DeviceRegistry } = require('../src/registry');

function registry(name) {
  process.env.REGISTRY_FILE = path.join(tmp, name);
  return new DeviceRegistry();
}

function seeded(name = 'seeded.json', overrides = {}) {
  const r = registry(name);
  const dev = r.register({
    id: 'dev1',
    name: 'old name',
    type: 'esp32-c3',
    ip: '10.0.0.7',
    port: 80,
    sensors: ['temp', 'hum'],
    ...overrides,
  });
  assert.ok(dev, 'seed device must register');
  return r;
}

test('update edits metadata in place', () => {
  const r = seeded();
  const before = r.get('dev1');

  const upd = r.update('dev1', { name: 'new name', type: 'esp32-c6', port: 8080 });
  assert.equal(upd.id, 'dev1');
  assert.equal(upd.name, 'new name');
  assert.equal(upd.type, 'esp32-c6');
  assert.equal(upd.port, 8080);
  assert.equal(upd.ip, '10.0.0.7');
  assert.deepEqual(upd.sensors, ['temp', 'hum']);

  const after = r.get('dev1');
  assert.equal(after.name, 'new name');
  assert.notEqual(after, before, 'update replaces the stored object');
  assert.equal(r.list().length, 1);
});

test('update keeps lifecycle fields untouched', () => {
  const r = seeded();
  const before = r.get('dev1');
  const seen = before.lastSeen;
  const firstSeen = before.firstSeen;

  const upd = r.update('dev1', { name: 'renamed' });
  assert.equal(upd.status, before.status);
  assert.equal(upd.lastSeen, seen);
  assert.equal(upd.firstSeen, firstSeen);
  assert.equal(upd.sensors, before.sensors);
});

test('update returns null for unknown devices and invalid patches', () => {
  const r = seeded();
  assert.equal(r.update('ghost', { name: 'x' }), null);
  assert.equal(r.update('dev1', null), null);
  assert.equal(r.update('dev1', undefined), null);
  assert.equal(r.update('dev1', 'name=string'), null);

  // An empty object is a valid no-op patch: the device comes back unchanged.
  const noop = r.update('dev1', {});
  assert.equal(noop.name, 'old name');
  assert.equal(noop.ip, '10.0.0.7');
});

test('update rejects invalid ip, port and sensors with EINVAL', () => {
  const r = seeded();
  const expectEinval = (patch, why) => {
    const err = r.update('dev1', patch);
    assert.ok(err instanceof Error, `expected an Error for ${why}`);
    assert.equal(err.code, 'EINVAL', `expected EINVAL for ${why}`);
  };

  expectEinval({ ip: 'not an ip' }, 'junk ip');
  expectEinval({ ip: '999.1.1.1' }, 'octet > 255');
  expectEinval({ ip: '10.0.0' }, 'too few octets');
  expectEinval({ ip: '' }, 'empty ip');
  expectEinval({ port: 0 }, 'port 0');
  expectEinval({ port: 65536 }, 'port > 65535');
  expectEinval({ port: 'eighty' }, 'non-numeric port');
  expectEinval({ sensors: 'temp' }, 'sensors not an array');

  const dev = r.get('dev1');
  assert.equal(dev.ip, '10.0.0.7');
  assert.equal(dev.port, 80);
  assert.deepEqual(dev.sensors, ['temp', 'hum']);
  assert.equal(dev.name, 'old name');
});

test('update accepts IPv4, bracketed IPv6 and IPv4-mapped forms', () => {
  const r = seeded();
  assert.equal(r.update('dev1', { ip: '192.168.1.50' }).ip, '192.168.1.50');
  assert.equal(r.update('dev1', { ip: '::1' }).ip, '::1');
  assert.equal(r.update('dev1', { ip: '[fe80::1]' }).ip, '[fe80::1]');
  assert.equal(r.update('dev1', { ip: '::ffff:127.0.0.1' }).ip, '::ffff:127.0.0.1');
  assert.equal(r.update('dev1', { port: 65535 }).port, 65535);
});

test('update truncates and dedupes name, type and sensors', () => {
  const r = seeded('trunc.json');
  const upd = r.update('dev1', {
    name: 'n'.repeat(300),
    type: 't'.repeat(200),
    sensors: ['a'.repeat(200), 'a'.repeat(200), 'b', '  b  '],
  });
  assert.equal(upd.name.length, 128);
  assert.equal(upd.type.length, 64);
  assert.equal(upd.sensors.length, 3, 'duplicates collapse, near-duplicates stay');
  assert.equal(upd.sensors[0].length, 64);
  assert.ok(upd.sensors.includes('b'));
});

test('update caps the sensor list at 64 entries', () => {
  const r = seeded('cap.json');
  const sensors = Array.from({ length: 100 }, (_, i) => `sensor-${i}`);
  const upd = r.update('dev1', { sensors });
  assert.equal(upd.sensors.length, 64);
  assert.equal(upd.sensors[0], 'sensor-0');
  assert.equal(upd.sensors[63], 'sensor-63');
});

test('empty name falls back to the reported name, empty type to a default', () => {
  const r = seeded('fallback.json');
  assert.equal(r.update('dev1', { name: '' }).name, 'old name');
  assert.equal(r.update('dev1', { type: '' }).type, 'esp32');
  assert.equal(r.update('dev1', { name: 42 }).name, '42');
});

test('custom name survives re-registration and can be cleared', () => {
  const r = registry('custom-name.json');
  r.register({ id: 'dev2', name: 'Main Controller', ip: '10.0.0.8', port: 80 });

  const renamed = r.update('dev2', { name: 'Kitchen' });
  assert.equal(renamed.name, 'Kitchen');
  assert.equal(renamed.customName, 'Kitchen');

  r.register({ id: 'dev2', name: 'Main Controller', ip: '10.0.0.8', port: 80 });
  assert.equal(r.get('dev2').name, 'Kitchen', 're-register keeps the custom name');

  const cleared = r.update('dev2', { name: '' });
  assert.equal(cleared.name, 'Main Controller', 'empty custom name falls back to the reported name');
});

test('update marks the registry dirty and survives a reload', () => {
  process.env.REGISTRY_FILE = path.join(tmp, 'persist.json');
  const a = new DeviceRegistry();
  a.register({ id: 'dev1', name: 'before', ip: '10.0.0.9', port: 80, sensors: [] });
  a.update('dev1', { name: 'after', sensors: ['voc'] });
  a.flush();

  const b = new DeviceRegistry();
  const dev = b.get('dev1');
  assert.equal(dev.name, 'after');
  assert.deepEqual(dev.sensors, ['voc']);

  b.remove('dev1');
  b.flush();
  assert.equal(new DeviceRegistry().get('dev1'), null);
});
