'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const { RulesEngine } = require('../src/rules_engine');

function fakeStore(rules) {
  return {
    list(filter = {}) {
      const result = rules.filter((r) => !filter.deviceId || r.device_id === filter.deviceId);
      return result.slice();
    },
  };
}

const fakeReg = (ids) => ({
  get(id) {
    return ids.has(String(id)) ? {} : null;
  },
});

function makeRule(over = {}) {
  return {
    id: 'r1',
    name: 'test',
    enabled: true,
    device_id: 'd1',
    trigger: 'threshold_above',
    sensor_type: 'temp',
    threshold: 30,
    action: 'mqtt_command',
    action_payload: 'relay:off',
    cooldown_seconds: 60,
    ...over,
  };
}

test('threshold_above fires once and publishes to iot/<device>/commands', () => {
  const rules = [makeRule()];
  let now = 0;
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry: fakeReg(new Set(['d1'])), now: () => now });
  const sent = [];
  const fired = [];
  engine.setPublish((t, p) => sent.push([t, p]));
  engine.on('fire', (info) => fired.push(info));

  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 31.5, t: 10, u: 'degC' });
  assert.equal(sent.length, 1, 'a crossing value must publish a command');
  assert.deepEqual(sent[0], ['iot/d1/commands', 'relay:off']);
  assert.equal(fired[0].action, 'mqtt_command');
  assert.equal(fired[0].snapshot.value, 31.5);

  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 40, t: 11 });
  assert.equal(sent.length, 1, 'cooldown must suppress a re-fire');

  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 20, t: 12 });
  assert.equal(sent.length, 1, 'a value below threshold never fires');

  now = 61_000;
  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 33, t: 61_010 });
  assert.equal(sent.length, 2, 'after the cooldown window another fire is allowed');
});

test('threshold_below fires on a low reading', () => {
  const rules = [makeRule({ trigger: 'threshold_below', threshold: 5, action_payload: 'heater:on' })];
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry: fakeReg(new Set(['d1'])) });
  const sent = [];
  engine.setPublish((t, p) => sent.push([t, p]));

  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 4.9 });
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0], ['iot/d1/commands', 'heater:on']);

  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 6 });
  assert.equal(sent.length, 1, 'a value above threshold must not fire threshold_below');
});

test('sensor_type filters the metric and the wildcard matches everything', () => {
  const rules = [makeRule({ sensor_type: 'bmp' })];
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry: fakeReg(new Set(['d1'])) });
  const sent = [];
  engine.setPublish((t, p) => sent.push([t, p]));

  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 99 });
  assert.equal(sent.length, 0, 'rule for bmp must ignore temp');

  const wild = [makeRule({ id: 'w1', sensor_type: '*' })];
  const engine2 = new RulesEngine({ ruleStore: fakeStore(wild), registry: fakeReg(new Set(['d1'])) });
  const sent2 = [];
  engine2.setPublish((t, p) => sent2.push([t, p]));
  engine2.onMetric({ deviceId: 'd1', sensor: 'hum', v: 90 });
  assert.equal(sent2.length, 1, 'a wildcard sensor_type matches any sensor');
});

test('disabled rules are never evaluated', () => {
  const rules = [makeRule({ enabled: false })];
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry: fakeReg(new Set(['d1'])) });
  let published = 0;
  engine.setPublish(() => {
    published += 1;
  });
  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 99 });
  assert.equal(published, 0);
});

test('unknown devices are ignored until registered', () => {
  const rules = [makeRule()];
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry: fakeReg(new Set(['known'])) });
  let published = 0;
  engine.setPublish(() => {
    published += 1;
  });
  engine.onMetric({ deviceId: 'ghost', sensor: 'temp', v: 50 });
  assert.equal(published, 0);
});

test('online/offline triggers fire on device status frames', () => {
  const rules = [makeRule({ trigger: 'offline', action: 'device_command', action_payload: 'power:off' })];
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry: fakeReg(new Set(['d1'])) });
  const sent = [];
  engine.setPublish((t, p) => sent.push([t, p]));

  engine.onStatus({ deviceId: 'd1', status: 'online', uptime: 1 });
  assert.equal(sent.length, 0, 'an online status must not fire an offline rule');

  engine.onStatus({ deviceId: 'd1', status: 'offline', uptime: 1 });
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0], ['iot/d1/commands', 'power:off']);
});

test('no_data fires when the device goes silent past the threshold', () => {
  const rules = [
    makeRule({ trigger: 'no_data', threshold: 300, action: 'notify' }),
  ];
  let now = 0;
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry: fakeReg(new Set(['d1'])), now: () => now });
  const fired = [];
  engine.on('fire', (info) => fired.push(info));
  engine.onMetric({ deviceId: 'd1', sensor: 'temp', v: 10, t: 0 });

  engine.tick();
  assert.equal(fired.length, 0, 'device is still within the silence budget');

  now = 301_000;
  engine.tick();
  assert.equal(fired.length, 1);
  assert.equal(fired[0].action, 'notify');
  assert.equal(fired[0].snapshot.type, 'no_data');

  engine.tick();
  assert.equal(fired.length, 1, 'cooldown must prevent duplicate notifications');
});

test('seedSilence pre-seeds silence from the registry last_seen', () => {
  const rules = [makeRule({ trigger: 'no_data', threshold: 60 })];
  let now = 100_000;
  const registry = {
    list() {
      return [{ id: 'd1', last_seen: 0 }, { id: 'd2' }];
    },
  };
  const engine = new RulesEngine({ ruleStore: fakeStore(rules), registry, now: () => now });
  const fired = [];
  engine.on('fire', (info) => fired.push(info));

  engine.seedSilence();
  now = 61_000;
  engine.tick();
  assert.equal(fired.length, 1, 'd1 seeded with last_seen=0 must be silent for 60s by now');
});