'use strict';

const net = require('net');
const { EventEmitter } = require('events');

/**
 * MqttClient — minimal MQTT 3.1.1 subscriber over a plain TCP socket.
 *
 * Zero dependencies by design: CONNECT/SUBSCRIBE/PING are encoded by hand and
 * PUBLISH frames are decoded as they arrive. The server uses it to bridge
 * sensor telemetry published by the firmware (iot/<deviceId>/sensors/<key>
 * and iot/<deviceId>/status) on the local mosquitto broker.
 *
 * Emits:
 *   'connect'      connected + CONNACK accepted
 *   'subscribed'   SUBACK received (subscribed? is always true for QoS 0)
 *   'message'      { topic, payload } for every PUBLISH it receives
 *   'metric'       { deviceId, sensor, timestamp, value, unit, topic }
 *   'status'       { deviceId, status, uptime, rssi, free_heap, chip_temp, modules }
 *   'error'        unrecoverable error (bad CONNACK, bad frame, ...)
 *   'close'        socket closed (auto-reconnect unless stopped)
 */

const PACKET = {
  CONNECT: 1,
  CONNACK: 2,
  PUBLISH: 3,
  PUBACK: 4,
  SUBSCRIBE: 8,
  SUBACK: 9,
  PINGREQ: 12,
  PINGRESP: 13,
  DISCONNECT: 14,
};

const CLEAN_SESSION = 0x02;
const FLAG_USERNAME = 0x80;
const FLAG_PASSWORD = 0x40;

const METRIC_RE = /^([^/]+)\/([^/]+)\/sensors\/([^/]+)$/;
const STATUS_RE = /^([^/]+)\/([^/]+)\/status$/;

const DEFAULT_RECONNECT_MIN_MS = 1000;
const DEFAULT_RECONNECT_MAX_MS = 60_000;

function encodeUtf(str) {
  const buf = Buffer.from(String(str), 'utf8');
  const out = Buffer.allocUnsafe(2 + buf.length);
  out.writeUInt16BE(buf.length, 0);
  buf.copy(out, 2);
  return out;
}

function encodeVarint(n) {
  const bytes = [];
  do {
    let byte = n % 128;
    n = Math.floor(n / 128);
    if (n > 0) byte |= 0x80;
    bytes.push(byte);
  } while (n > 0);
  return Buffer.from(bytes);
}

function decodeVarint(buf, offset) {
  let value = 0;
  let shift = 0;
  let i = offset;
  for (;;) {
    if (i >= buf.length) return { value: -1, length: 0 };
    const byte = buf[i++];
    value += (byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) break;
    shift += 7;
    if (shift >= 28) return { value: -1, length: 0 };
  }
  return { value, length: i - offset };
}

function readUtf(buf, offset) {
  if (offset + 2 > buf.length) return null;
  const len = buf.readUInt16BE(offset);
  if (offset + 2 + len > buf.length) return null;
  return { value: buf.toString('utf8', offset + 2, offset + 2 + len), next: offset + 2 + len };
}

function connackMessage(code) {
  const body = Buffer.from([0x00, code]);
  return Buffer.concat([Buffer.from([PACKET.CONNACK << 4]), encodeVarint(body.length), body]);
}

/** Incrementally assembles complete MQTT frames from a byte stream. */
class FrameParser {
  constructor() {
    this.buf = Buffer.alloc(0);
  }

  push(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    const frames = [];
    for (;;) {
      const frame = this._next();
      if (!frame) break;
      frames.push(frame);
    }
    return frames;
  }

  _next() {
    if (this.buf.length < 2) return null;
    const { value: remLen, length: remBytes } = decodeVarint(this.buf, 1);
    if (remLen < 0 || remBytes <= 0) return null;
    const total = 1 + remBytes + remLen;
    if (this.buf.length < total) return null;

    const header = this.buf[0];
    const body = Buffer.from(this.buf.subarray(1 + remBytes, total));
    this.buf = Buffer.from(this.buf.subarray(total));
    return { type: header >> 4, flags: header & 0x0f, body, remLen };
  }
}

class MqttClient extends EventEmitter {
  constructor(opts = {}) {
    super();
    this.host = opts.host || '127.0.0.1';
    this.port = opts.port || 1883;
    this.user = opts.user !== undefined ? opts.user : 'app';
    this.password = opts.password !== undefined ? opts.password : '';
    this.clientId = opts.clientId || 'iot-server';
    this.topic = opts.topic || 'iot/+/#';
    this.keepalive = opts.keepalive || 30;
    this.reconnectMinMs = opts.reconnectMinMs || DEFAULT_RECONNECT_MIN_MS;
    this.reconnectMaxMs = opts.reconnectMaxMs || DEFAULT_RECONNECT_MAX_MS;

    this.socket = null;
    this.parser = new FrameParser();
    this.stopped = false;
    this.reconnectMs = this.reconnectMinMs;
    this.reconnectTimer = null;
    this.pingTimer = null;
    this.pingWaitTimer = null;
    this.nextPingAt = 0;
    this.expectingPingResp = false;
  }

  start() {
    this.stopped = false;
    this._connect();
    return this;
  }

  stop() {
    this.stopped = true;
    this._clearTimers();
    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }
    return this;
  }

  _clearTimers() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
    if (this.pingWaitTimer) {
      clearTimeout(this.pingWaitTimer);
      this.pingWaitTimer = null;
    }
  }

  _connect() {
    if (this.stopped || this.socket) return;

    const sock = net.createConnection({ host: this.host, port: this.port });
    this.socket = sock;
    this.parser = new FrameParser();
    this.expectingPingResp = false;

    sock.on('connect', () => {
      const packet = this._buildConnect();
      sock.write(packet);
      this._startPingLoop();
    });

    sock.on('data', (chunk) => {
      let frames;
      try {
        frames = this.parser.push(chunk);
      } catch (e) {
        this.emit('error', e);
        sock.destroy();
        return;
      }
      for (const frame of frames) this._handleFrame(frame);
    });

    sock.on('error', (err) => this.emit('error', err));

    sock.on('close', () => {
      if (this.socket === sock) this.socket = null;
      this._stopPingLoop();
      this.emit('close');
      this._scheduleReconnect();
    });
  }

  _buildConnect() {
    const flags =
      CLEAN_SESSION |
      (this.user || this.password ? FLAG_USERNAME : 0) |
      (this.password ? FLAG_PASSWORD : 0);

    const body = Buffer.concat([
      encodeUtf('MQTT'),          // protocol name
      Buffer.from([0x04]),        // protocol level 4 (MQTT 3.1.1)
      Buffer.from([flags]),
      Buffer.from([this.keepalive >> 8, this.keepalive & 0xff]),
      encodeUtf(this.clientId),
      this.user ? encodeUtf(this.user) : Buffer.alloc(0),
      this.user && this.password ? encodeUtf(this.password) : Buffer.alloc(0),
    ]);
    return Buffer.concat([Buffer.from([PACKET.CONNECT << 4]), encodeVarint(body.length), body]);
  }

  _buildSubscribe() {
    const body = Buffer.concat([
      Buffer.from([0x00, 0x01]),              // packet id 1
      encodeUtf(this.topic),
      Buffer.from([0x00]),                    // requested QoS 0
    ]);
    return Buffer.concat([Buffer.from([(PACKET.SUBSCRIBE << 4) | 0x02]), encodeVarint(body.length), body]);
  }

  /**
   * Publish a QoS 0 message (outbound command channel iot/<deviceId>/commands).
   * Returns false when not connected.
   */
  publish(topic, payload) {
    if (!this.socket) return false;
    const t = encodeUtf(String(topic));
    const p = Buffer.isBuffer(payload)
      ? payload
      : Buffer.from(String(payload == null ? '' : payload), 'utf8');
    const body = Buffer.concat([t, p]);
    const packet = Buffer.concat([
      Buffer.from([(PACKET.PUBLISH << 4) | 0x00]),
      encodeVarint(body.length),
      body,
    ]);
    this.socket.write(packet);
    return true;
  }

  _buildPing() {
    return Buffer.from([PACKET.PINGREQ << 4, 0x00]);
  }

  _handleFrame(frame) {
    switch (frame.type) {
      case PACKET.CONNACK: {
        const code = frame.body[1];
        if (code !== 0) {
          this.emit('error', new Error(`mqtt CONNACK rejected (code ${code})`));
          this.socket && this.socket.destroy();
          return;
        }
        this.reconnectMs = this.reconnectMinMs;
        const subscribe = this._buildSubscribe();
        this.socket && this.socket.write(subscribe);
        this.emit('connect');
        break;
      }
      case PACKET.SUBACK:
        this.emit('subscribed');
        break;
      case PACKET.PINGRESP:
        this.expectingPingResp = false;
        break;
      case PACKET.PUBLISH:
        this._handlePublish(frame);
        break;
      default:
        break;
    }
  }

  _handlePublish(frame) {
    const topic = readUtf(frame.body, 0);
    if (!topic) return;

    let offset = topic.next;
    const qos = (frame.flags >> 1) & 0x03;
    if (qos > 0) offset += 2; // packet id (never requested, but be tolerant)

    const payload = frame.body.toString('utf8', offset);
    let parsed = null;
    try {
      parsed = payload ? JSON.parse(payload) : null;
    } catch {
      parsed = null;
    }

    this.emit('message', { topic: topic.value, payload });

    const m = topic.value.match(METRIC_RE);
    if (m) {
      // Only forward well-formed telemetry: a missing/unparseable payload or a
      // non-numeric value is dropped (the raw message was already emitted).
      const value = parsed && typeof parsed === 'object' && parsed.value !== undefined
        ? Number(parsed.value)
        : NaN;
      if (Number.isFinite(value)) {
        this.emit('metric', {
          deviceId: m[2],
          sensor: m[3],
          timestamp: parsed && Number.isFinite(Number(parsed.timestamp)) ? Number(parsed.timestamp) : Date.now(),
          value,
          unit: parsed && typeof parsed.unit === 'string' ? parsed.unit : null,
          topic: topic.value,
          payload,
        });
      }
      return;
    }

    const st = topic.value.match(STATUS_RE);
    if (st) {
      this.emit('status', {
        deviceId: st[2],
        status: parsed && parsed.status ? String(parsed.status) : 'unknown',
        uptime: parsed && Number.isFinite(Number(parsed.uptime)) ? Number(parsed.uptime) : null,
        rssi: parsed && Number.isFinite(Number(parsed.rssi)) ? Number(parsed.rssi) : null,
        free_heap: parsed && Number.isFinite(Number(parsed.free_heap)) ? Number(parsed.free_heap) : null,
        chip_temp: parsed && Number.isFinite(Number(parsed.chip_temp)) ? Number(parsed.chip_temp) : null,
        modules: parsed && Array.isArray(parsed.modules) ? parsed.modules.map(String) : [],
        topic: topic.value,
      });
    }
  }

  _startPingLoop() {
    this._stopPingLoop();
    if (this.keepalive <= 0) return;
    this.pingTimer = setInterval(() => {
      if (!this.socket) return;
      if (this.expectingPingResp) {
        this.socket.destroy();
        return;
      }
      this.expectingPingResp = true;
      this.socket.write(this._buildPing());
      this.pingWaitTimer = setTimeout(() => {
        if (this.expectingPingResp && this.socket) this.socket.destroy();
      }, this.keepalive * 1000 * 1.5).unref();
    }, this.keepalive * 1000);
    this.pingTimer.unref();
  }

  _stopPingLoop() {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
    if (this.pingWaitTimer) {
      clearTimeout(this.pingWaitTimer);
      this.pingWaitTimer = null;
    }
    this.expectingPingResp = false;
  }

  _scheduleReconnect() {
    if (this.stopped || this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (!this.stopped) this._connect();
    }, this.reconnectMs);
    this.reconnectTimer.unref();
    this.reconnectMs = Math.min(this.reconnectMaxMs, Math.floor(this.reconnectMs * 2));
  }
}

function createMqttClient(opts) {
  return new MqttClient(opts);
}

module.exports = { MqttClient, createMqttClient, FrameParser, PACKET, connackMessage };