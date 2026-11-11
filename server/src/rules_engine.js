'use strict';

const { EventEmitter } = require('node:events');

/**
 * RulesEngine — server-side evaluation of smart-home rules against incoming
 * MQTT telemetry. Evaluated in-process so rules can react to live data:
 *
 *   thresholds    rule.trigger === 'threshold_above' / 'threshold_below'
 *                 fires when a metric for rule.sensor_type (or '*') crosses
 *   presence      'online' / 'offline' — device status transitions
 *   no_data       fires when the device goes silent for rule.threshold seconds
 *
 * Actions are dispatched via the injected publish(topic, payload) function
 * (the MQTT client) and events:
 *
 *   fire          { rule, snapshot, action, topic, payload }
 *                 emitted after any successful dispatch (SSE 'rule' frames)
 *   publish       (topic, payload) — raw command published (for spies)
 *
 * Cooldown per rule id is enforced in memory from rule.cooldown_seconds.
 */

class RulesEngine extends EventEmitter {
  constructor({ ruleStore, registry, telemetry, now = () => Date.now() }) {
    super();
    this.ruleStore = ruleStore;
    this.registry = registry;
    this.telemetry = telemetry;
    this._now = now;
    this.publish = () => {};
    this._cooldown = new Map();  // rule id -> last fire epoch ms
    this._silence = new Map();   // deviceId -> last traffic epoch ms
    this._timer = null;
  }

  /** Seed per-device silence baseline from the registry (last_seen). */
  seedSilence() {
    if (!this.registry) return;
    for (const d of this.registry.list({ all: true })) {
      if (d && typeof d.last_seen === 'number') this._silence.set(d.id, d.last_seen);
    }
  }

  start(intervalMs = 30_000) {
    if (this._timer) return this;
    this.seedSilence();
    this._timer = setInterval(() => this.tick(), intervalMs);
    if (typeof this._timer.unref === 'function') this._timer.unref();
    return this;
  }

  stop() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
    return this;
  }

  setPublish(fn) {
    if (typeof fn === 'function') this.publish = fn;
    return this;
  }

  _due(rule) {
    const last = this._cooldown.get(rule.id);
    if (last === undefined) return true; // never fired before
    return this._now() - last >= rule.cooldown_seconds * 1000;
  }

  _touch(deviceId, ts) {
    if (deviceId) this._silence.set(String(deviceId), ts);
  }

  _fire(rule, snapshot) {
    if (this._due(rule)) this._cooldown.set(rule.id, this._now());

    const isMqttAction = rule.action === 'mqtt_command' || rule.action === 'device_command';
    let topic;
    let payload;
    if (isMqttAction) {
      topic = `iot/${rule.device_id}/commands`;
      payload = String(rule.action_payload || '');
      this.publish(topic, payload);
    }

    this.emit('fire', {
      rule,
      action: rule.action,
      topic: topic || null,
      payload: payload || null,
      snapshot,
      ts: this._now(),
    });
  }

  _matchesSensor(rule, sensor) {
    if (rule.trigger !== 'threshold_above' && rule.trigger !== 'threshold_below') return true;
    return rule.sensor_type === '*' || rule.sensor_type === sensor;
  }

  /** Evaluate an incoming live metric. */
  onMetric(m) {
    if (!m || !m.deviceId) return;
    const deviceId = String(m.deviceId);
    const ts = Number.isFinite(m.t) ? m.t : m.timestamp;
    this._touch(deviceId, Number.isFinite(ts) ? ts : this._now());
    if (this.registry && !this.registry.get(deviceId)) return;
    if (!Number.isFinite(m.v)) return;

    for (const rule of this.ruleStore.list({ deviceId })) {
      if (!rule.enabled) continue;
      if (rule.trigger !== 'threshold_above' && rule.trigger !== 'threshold_below') continue;
      if (!this._matchesSensor(rule, m.sensor)) continue;

      const hit =
        rule.trigger === 'threshold_above' ? m.v > rule.threshold : m.v < rule.threshold;
      if (hit && this._due(rule)) {
        this._fire(rule, { type: 'metric', deviceId, sensor: m.sensor, value: m.v, unit: m.u, ts });
      }
    }
  }

  /** Evaluate an incoming device status frame. */
  onStatus(s) {
    if (!s || !s.deviceId) return;
    const deviceId = String(s.deviceId);
    this._touch(deviceId, this._now());
    if (this.registry && !this.registry.get(deviceId)) return;

    for (const rule of this.ruleStore.list({ deviceId })) {
      if (!rule.enabled) continue;
      if (rule.trigger !== 'online' && rule.trigger !== 'offline') continue;
      if (String(s.status).toLowerCase() === rule.trigger && this._due(rule)) {
        this._fire(rule, { type: 'status', deviceId, status: s.status, uptime: s.uptime });
      }
    }
  }

  /** Periodic scan: no_data rules against the silence map. */
  tick() {
    const now = this._now();
    for (const rule of this.ruleStore.list()) {
      if (!rule.enabled || rule.trigger !== 'no_data') continue;
      const last = this._silence.get(rule.device_id);
      if (last == null) continue;
      const thresholdMs = (rule.threshold > 0 ? rule.threshold : 300) * 1000;
      if (now - last >= thresholdMs && this._due(rule)) {
        this._fire(rule, { type: 'no_data', deviceId: rule.device_id, since: last, now });
      }
    }
  }
}

module.exports = { RulesEngine };