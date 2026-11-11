'use strict';

const fs = require('fs');
const path = require('path');
const config = require('./config');
const { downsample } = require('./metrics');

/**
 * TelemetryStore — persistent sensor-value storage for the MQTT bridge.
 *
 * Layout under `<dir>`:
 *   raw/<device>/<sensor>/<YYYY-MM-DDTHH>.jsonl   one JSON line per sample
 *   rollup/<device>/<sensor>.jsonl                hourly summaries
 *   latest.json                                   last value per device/sensor
 *
 * Samples are appended synchronously (volume is tiny), so a crashed process
 * never loses a line; hourly rollups summarize closed hours for cheap history.
 * Memory use is bounded by devices×sensors (one small accumulator per key).
 */

const NAME_RE = /^[A-Za-z0-9_.:+-]+$/;
const MAX_NAME_LEN = 64;

function safeComponent(name) {
  const s = String(name == null ? '' : name);
  if (s.length === 0 || s.length > MAX_NAME_LEN) return null;
  if (s === '.' || s === '..') return null;
  if (!NAME_RE.test(s)) return null;
  return s;
}

function hourOf(t) {
  const d = new Date(Math.floor(Number(t) || 0));
  const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(d.getUTCDate()).padStart(2, '0');
  const hh = String(d.getUTCHours()).padStart(2, '0');
  return `${d.getUTCFullYear()}-${mm}-${dd}T${hh}`;
}

function hourStart(hs) {
  return Date.parse(`${hs}:00:00Z`);
}

function nextHour(hs) {
  return hourOf(hourStart(hs) + 3600 * 1000);
}

class TelemetryStore {
  constructor({ dir, latestFile, flushSeconds } = {}) {
    this.dir = dir || config.ingest.dir;
    this.latestFile = latestFile || config.ingest.latestFile;

    this.rawDir = path.join(this.dir, 'raw');
    this.rollDir = path.join(this.dir, 'rollup');
    this.rollAcc = new Map();     // key -> { hour, unit, count, min, max, sum, firstT, firstV, lastT, lastV }
    this.latest = new Map();      // deviceId -> sensor -> { t, v, u }

    this._lastLatestDebounce = 0;
    this._latestTimer = null;
    this._loadLatest();
    this._mkdir(this.rawDir);
    this._mkdir(this.rollDir);

    const fl = flushSeconds || config.ingest.flushSeconds;
    this.flushTimer = setInterval(() => this.flush(), fl * 1000);
    this.flushTimer.unref();
  }

  _mkdir(dir) {
    try {
      fs.mkdirSync(dir, { recursive: true });
    } catch (e) {
      console.error(`[ingest] cannot create ${dir}: ${e.message}`);
    }
  }

  _loadLatest() {
    try {
      const raw = fs.readFileSync(this.latestFile, 'utf8');
      const data = JSON.parse(raw);
      if (data && typeof data === 'object') {
        for (const dev of Object.keys(data)) {
          if (!data[dev] || typeof data[dev] !== 'object') continue;
          this.latest.set(dev, data[dev]);
        }
      }
    } catch {
      /* first run or corrupt file */
    }
  }

  _saveLatestNow() {
    const out = {};
    for (const [dev, sensors] of this.latest) out[dev] = sensors;
    try {
      const dir = path.dirname(this.latestFile);
      this._mkdir(dir);
      const tmp = this.latestFile + '.tmp';
      fs.writeFileSync(tmp, JSON.stringify(out));
      fs.renameSync(tmp, this.latestFile);
    } catch (e) {
      console.error(`[ingest] failed to save latest: ${e.message}`);
    }
    this._latestTimer = null;
    this._lastLatestDebounce = 0;
  }

  _scheduleLatestSave() {
    const now = Date.now();
    if (this._latestTimer) return;
    const delay = Math.max(0, LATEST_DEBOUNCE_MS - (now - this._lastLatestDebounce));
    this._latestTimer = setTimeout(() => this._saveLatestNow(), delay);
    this._latestTimer.unref();
  }

  rawFile(deviceId, sensor, hour) {
    return path.join(this.rawDir, deviceId, sensor, `${hour}.jsonl`);
  }

  rollFile(deviceId, sensor) {
    return path.join(this.rollDir, deviceId, `${sensor}.jsonl`);
  }

  keyOf(deviceId, sensor) {
    return `${deviceId}\u0001${sensor}`;
  }

  /**
   * Accept a sample { deviceId, sensor, timestamp, value, unit }.
   * Returns false when the sample is malformed (and logs nothing).
   */
  append(sample) {
    const deviceId = safeComponent(sample && sample.deviceId);
    const sensor = safeComponent(sample && sample.sensor);
    const value = Number(sample && sample.value);
    const t = Number(sample && sample.timestamp);
    if (!deviceId || !sensor) return false;
    if (!Number.isFinite(value) || !Number.isFinite(t) || t <= 0) return false;
    const unit = sample.unit && typeof sample.unit === 'string' ? sample.unit : null;

    const hour = hourOf(t);
    const k = this.keyOf(deviceId, sensor);

    let acc = this.rollAcc.get(k);
    if (!acc || acc.hour !== hour) {
      if (acc) this._finalizeRoll(k, acc);
      acc = {
        hour,
        unit,
        count: 0,
        min: Infinity,
        max: -Infinity,
        sum: 0,
        firstT: t,
        firstV: value,
        lastT: t,
        lastV: value,
      };
      this.rollAcc.set(k, acc);
    }

    acc.count += 1;
    if (value < acc.min) acc.min = value;
    if (value > acc.max) acc.max = value;
    acc.sum += value;
    acc.lastT = t;
    acc.lastV = value;

    const file = this.rawFile(deviceId, sensor, hour);
    this._mkdir(path.dirname(file));
    try {
      fs.appendFileSync(file, JSON.stringify({ t, v: value, u: unit }) + '\n');
    } catch (e) {
      console.error(`[ingest] append failed (${file}): ${e.message}`);
      return false;
    }

    let sensors = this.latest.get(deviceId);
    if (!sensors) {
      sensors = {};
      this.latest.set(deviceId, sensors);
    }
    sensors[sensor] = { t, v: value, u: unit };
    this._scheduleLatestSave();

    return true;
  }

  _finalizeRoll(k, acc) {
    const [deviceId, sensor] = k.split('\u0001');
    const file = this.rollFile(deviceId, sensor);
    this._mkdir(path.dirname(file));
    const line = {
      h: acc.hour,
      unit: acc.unit,
      count: acc.count,
      min: acc.min,
      max: acc.max,
      sum: Math.round(acc.sum * 100) / 100,
      avg: Math.round((acc.sum / acc.count) * 100) / 100,
      first_t: acc.firstT,
      first_v: acc.firstV,
      last_t: acc.lastT,
      last_v: acc.lastV,
    };
    try {
      fs.appendFileSync(file, JSON.stringify(line) + '\n');
    } catch (e) {
      console.error(`[ingest] rollup write failed: ${e.message}`);
    }
    this.rollAcc.delete(k);
  }

  /** Close rolls and streams whose hour has already ended. */
  flush() {
    const currentHour = hourOf(Date.now());
    for (const k of [...this.rollAcc.keys()]) {
      if (this.rollAcc.get(k).hour !== currentHour) this._finalizeRoll(k, this.rollAcc.get(k));
    }
    if (this._latestTimer) {
      clearTimeout(this._latestTimer);
      this._saveLatestNow();
    }
  }

  close() {
    for (const k of [...this.rollAcc.keys()]) this._finalizeRoll(k, this.rollAcc.get(k));
    if (this.flushTimer) clearInterval(this.flushTimer);
    if (this._latestTimer) {
      clearTimeout(this._latestTimer);
      this._saveLatestNow();
    }
    this.flushTimer = null;
    this._latestTimer = null;
  }

  /** Last accepted value per sensor for one device (or all devices). */
  latestValues(deviceId = null) {
    if (deviceId) {
      const sensors = this.latest.get(String(deviceId));
      return sensors ? { ...sensors } : null;
    }
    const out = {};
    for (const [dev, sensors] of this.latest) out[dev] = { ...sensors };
    return out;
  }

  stats() {
    let sensors = 0;
    for (const sensorsMap of this.latest.values()) sensors += Object.keys(sensorsMap).length;
    return { devices: this.latest.size, sensors };
  }

  /**
   * Time series for one device/sensor inside [from, to], downsampled to
   * `points`. Returns `[{ t, v, u }]` sorted by t ascending.
   */
  query(deviceId, sensor, { from, to = Date.now(), points = 120 } = {}) {
    deviceId = safeComponent(deviceId);
    sensor = safeComponent(sensor);
    const t0 = Number.isFinite(Number(from)) ? Number(from) : to - 24 * 3600 * 1000;
    const t1 = Number.isFinite(Number(to)) ? Number(to) : Date.now();
    if (!deviceId || !sensor || t1 <= t0) return [];

    const series = [];
    let lastU = null;
    for (let hs = hourOf(t0); hourStart(hs) <= t1; hs = nextHour(hs)) {
      const file = this.rawFile(deviceId, sensor, hs);
      let lines;
      try {
        lines = fs.readFileSync(file, 'utf8').split('\n');
      } catch {
        continue;
      }
      for (const line of lines) {
        if (!line) continue;
        let rec = null;
        try {
          rec = JSON.parse(line);
        } catch {
          continue;
        }
        if (!rec || !Number.isFinite(rec.t) || !Number.isFinite(rec.v)) continue;
        if (rec.t < t0 || rec.t > t1) continue;
        if (rec.u) lastU = rec.u;
        series.push({ t: rec.t, v: rec.v });
      }
    }
    series.sort((a, b) => a.t - b.t);
    const maxPoints = Math.max(2, Math.min(600, Number(points) || 120));
    if (series.length <= maxPoints) {
      return series.map((s) => ({ t: s.t, v: s.v, u: lastU }));
    }
    const out = downsample(series, maxPoints);
    return out.map((s) => ({ t: s.t, v: s.v, u: lastU }));
  }
}

const LATEST_DEBOUNCE_MS = 2000;

module.exports = { TelemetryStore, hourOf, hourStart, safeComponent, downsample };