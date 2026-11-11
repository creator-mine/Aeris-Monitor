'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const net = require('net');

const { MqttClient, FrameParser, PACKET, connackMessage } = require('../src/mqtt_client');

/* ---------- low-level protocol helpers (firmware-side of the wire) ---------- */

function encodeUtf(str) {
  const buf = Buffer.from(String(str), 'utf8');
  const out = Buffer.alloc(2 + buf.length);
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

function publishFrame(topic, payload) {
  const body = Buffer.concat([encodeUtf(topic), Buffer.from(payload, 'utf8')]);
  return Buffer.concat([Buffer.from([PACKET.PUBLISH << 4]), encodeVarint(body.length), body]);
}

function subackFrame(packetId, count) {
  const body = Buffer.concat([Buffer.from([packetId >> 8, packetId & 0xff]), Buffer.alloc(count)]);
  return Buffer.concat([Buffer.from([PACKET.SUBACK << 4]), encodeVarint(body.length), body]);
}

function parseConnect(body) {
  const protoLen = body.readUInt16BE(0);
  const proto = body.toString('utf8', 2, 2 + protoLen);
  let o = 2 + protoLen;
  const level = body[o++];
  const flags = body[o++];
  const keepalive = body.readUInt16BE(o);
  o += 2;
  const clientIdLen = body.readUInt16BE(o);
  o += 2;
  const clientId = body.toString('utf8', o, o + clientIdLen);
  o += clientIdLen;
  let user = null;
  if (flags & 0x80) {
    const len = body.readUInt16BE(o);
    o += 2;
    user = body.toString('utf8', o, o + len);
    o += len;
  }
  let password = null;
  if (flags & 0x40) {
    const len = body.readUInt16BE(o);
    o += 2;
    password = body.toString('utf8', o, o + len);
    o += len;
  }
  return { proto, level, flags, keepalive, clientId, user, password };
}

function parseSubscribe(body) {
  const packetId = body.readUInt16BE(0);
  let o = 2;
  const filters = [];
  while (o + 1 < body.length) {
    const len = body.readUInt16BE(o);
    filters.push({ topic: body.toString('utf8', o + 2, o + 2 + len), qos: body[o + 2 + len] });
    o += 2 + len + 1;
  }
  return { packetId, filters };
}

/* ---------- fake broker ---------- */

function createFakeBroker({ connackCode = 0, respondToPings = true } = {}) {
  return new Promise((resolve) => {
    const sockets = [];
    let accepted = 0;
    let connectInfo = null;
    let subscribeInfo = null;
    let pingCount = 0;
    const publishes = [];

    const server = net.createServer((socket) => {
      accepted += 1;
      sockets.push(socket);
      const parser = new FrameParser();
      socket.on('data', (chunk) => {
        for (const f of parser.push(chunk)) {
          if (f.type === PACKET.CONNECT) {
            connectInfo = parseConnect(f.body);
            socket.write(connackMessage(connackCode));
          } else if (f.type === PACKET.SUBSCRIBE) {
            subscribeInfo = parseSubscribe(f.body);
            socket.write(subackFrame(subscribeInfo.packetId, subscribeInfo.filters.length));
          } else if (f.type === PACKET.PINGREQ) {
            pingCount += 1;
            if (respondToPings) socket.write(Buffer.from([PACKET.PINGRESP << 4, 0x00]));
          } else if (f.type === PACKET.PUBLISH) {
            const topicLen = f.body.readUInt16BE(0);
            const topic = f.body.toString('utf8', 2, 2 + topicLen);
            const payload = f.body.toString('utf8', 2 + topicLen);
            publishes.push({ topic, payload, flags: f.flags });
          }
        }
      });
    });

    server.listen(0, '127.0.0.1', () => {
      resolve({
        server,
        sockets,
        get accepted() {
          return accepted;
        },
        get connectInfo() {
          return connectInfo;
        },
        get subscribeInfo() {
          return subscribeInfo;
        },
        get pingCount() {
          return pingCount;
        },
        get publishes() {
          return publishes;
        },
        port: server.address().port,
        publish: (topic, payload) => sockets.forEach((s) => s.write(publishFrame(topic, payload))),
        kill: (i = 0) => sockets[i] && sockets[i].destroy(),
      });
    });
  });
}

function once(client, event, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timeout waiting for '${event}'`)), timeoutMs);
    client.once(event, (...args) => {
      clearTimeout(timer);
      resolve(args.length > 1 ? args : args[0]);
    });
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function makeClient(broker, opts = {}) {
  return new MqttClient({
    host: '127.0.0.1',
    port: broker.port,
    user: 'app',
    password: 'app-password',
    clientId: 'test-shell',
    topic: 'iot/+/#',
    keepalive: 10,
    reconnectMinMs: 40,
    reconnectMaxMs: 200,
    ...opts,
  });
}

/* ---------- FrameParser ---------- */

test('FrameParser reassembles split packets', () => {
  const parser = new FrameParser();
  const frames = parser.push(Buffer.from([PACKET.CONNACK << 4, 0x02, 0x00, 0x00]));
  assert.equal(frames.length, 1);
  assert.equal(frames[0].type, PACKET.CONNACK);
  assert.deepEqual(frames[0].body, Buffer.from([0x00, 0x00]));

  const ping = parser.push(Buffer.from([PACKET.PINGRESP << 4]));
  assert.equal(ping.length, 0, 'incomplete frame is buffered');
  assert.equal(parser.push(Buffer.from([0x00])).length, 1, 'completion flushes the frame');
});

test('FrameParser handles a multi-byte remaining length', () => {
  const parser = new FrameParser();
  const body = Buffer.alloc(130, 0x41);
  const frame = Buffer.concat([Buffer.from([PACKET.PUBLISH << 4]), encodeVarint(130), body]);
  const out = parser.push(Buffer.from(frame));
  assert.equal(out.length, 1);
  assert.equal(out[0].remLen, 130);
  assert.equal(out[0].body.length, 130);
});

test('FrameParser buffers a PUBLISH split across many chunks', async () => {
  const parser = new FrameParser();
  const body = Buffer.alloc(50, 0x42);
  const frame = Buffer.concat([Buffer.from([PACKET.PUBLISH << 4]), encodeVarint(body.length), body]);
  let assembled = 0;
  for (const chunk of frame) {
    assembled += parser.push(Buffer.from([chunk])).length;
  }
  assert.equal(assembled, 1);
});

/* ---------- handshake ---------- */

test('connects, authenticates and subscribes through the broker handshake', async () => {
  const broker = await createFakeBroker();
  const client = makeClient(broker);
  const events = [];
  client.on('connect', () => events.push('connect'));
  client.on('subscribed', () => events.push('subscribed'));

  const subscribed = once(client, 'subscribed');
  client.start();
  await subscribed;

  assert.deepEqual(events, ['connect', 'subscribed']);

  const c = broker.connectInfo;
  assert.equal(c.proto, 'MQTT');
  assert.equal(c.level, 4);
  assert.equal(c.clientId, 'test-shell');
  assert.equal(c.user, 'app');
  assert.equal(c.password, 'app-password');
  assert.equal(c.keepalive, 10);
  assert.ok(c.flags & (1 << 1), 'clean session flag set');

  assert.ok(broker.subscribeInfo, 'SUBSCRIBE received');
  assert.deepEqual(broker.subscribeInfo.filters, [{ topic: 'iot/+/#', qos: 0 }]);

  client.stop();
  broker.server.close();
});

/* ---------- message delivery ---------- */

test('delivers PUBLISH metrics and status events', async () => {
  const broker = await createFakeBroker();
  const client = makeClient(broker);
  const subscribed = once(client, 'subscribed');
  client.start();
  await subscribed;

  const metricP = once(client, 'metric');
  broker.publish(
    'iot/esp32c3_001/sensors/temp',
    JSON.stringify({ device_id: 'esp32c3_001', sensor: 'temp', timestamp: 1700000000000, value: 23.45, unit: 'degC' }),
  );
  const statusTopic = 'iot/esp32c3_001/status';
  const statusP = once(client, 'status');
  broker.publish(
    statusTopic,
    JSON.stringify({ device_id: 'esp32c3_001', status: 'online', uptime: 42, rssi: -61, free_heap: 123456, modules: ['bme680'] }),
  );

  const metric = await metricP;
  const status = await statusP;

  assert.equal(metric.deviceId, 'esp32c3_001');
  assert.equal(metric.sensor, 'temp');
  assert.equal(metric.value, 23.45);
  assert.equal(metric.unit, 'degC');
  assert.equal(metric.timestamp, 1700000000000);
  assert.equal(metric.topic, 'iot/esp32c3_001/sensors/temp');

  assert.equal(status.deviceId, 'esp32c3_001');
  assert.equal(status.status, 'online');
  assert.equal(status.uptime, 42);
  assert.equal(status.rssi, -61);
  assert.equal(status.free_heap, 123456);
  assert.deepEqual(status.modules, ['bme680']);
  assert.equal(status.topic, statusTopic);

  client.stop();
  broker.server.close();
});

test('publishes a QoS 0 command to the iot/<device>/commands channel', async () => {
  const broker = await createFakeBroker();
  const client = makeClient(broker);
  const subscribed = once(client, 'subscribed');
  client.start();
  await subscribed;

  const payload = JSON.stringify({ cmd: 'relay', state: 1 });
  assert.equal(client.publish('iot/esp32c3_001/commands', payload), true);

  await sleep(50);
  assert.equal(broker.publishes.length, 1);
  assert.equal(broker.publishes[0].topic, 'iot/esp32c3_001/commands');
  assert.equal(broker.publishes[0].payload, payload);
  assert.equal((broker.publishes[0].flags >> 1) & 0x03, 0, 'must be QoS 0');

  client.stop();
  broker.server.close();
});

test('emits raw message events and tolerates non-JSON payloads', async () => {
  const broker = await createFakeBroker();
  const client = makeClient(broker);
  const subscribed = once(client, 'subscribed');
  client.start();
  await subscribed;

  const msgP = once(client, 'message');
  broker.publish('iot/dev9/sensors/bad', 'not-json-at-all');

  const msg = await msgP;
  assert.equal(msg.topic, 'iot/dev9/sensors/bad');
  assert.equal(msg.payload, 'not-json-at-all');

  client.stop();
  broker.server.close();
});

test('drops a value for an unparseable metric topic', async () => {
  const broker = await createFakeBroker();
  const client = makeClient(broker);
  const subscribed = once(client, 'subscribed');
  client.start();
  await subscribed;

  let metricCount = 0;
  client.on('metric', () => {
    metricCount += 1;
  });
  broker.publish('iot/dev1/sensors/temp', 'garbage');

  await sleep(150);
  assert.equal(metricCount, 0, 'a malformed sensor payload must not emit a metric');
  assert.equal(broker.sockets[0].destroyed, false);

  client.stop();
  broker.server.close();
});

/* ---------- keepalive ---------- */

test('keeps the connection alive with PINGREQ/PINGRESP', async () => {
  const broker = await createFakeBroker();
  const client = makeClient(broker, { keepalive: 1 });
  const subscribed = once(client, 'subscribed');
  client.start();
  await subscribed;

  const t0 = Date.now();
  while (broker.pingCount < 1 && Date.now() < t0 + 3500) await sleep(50);
  assert.ok(broker.pingCount >= 1, 'client must send PINGREQ');

  const alive = broker.sockets[0] && !broker.sockets[0].destroyed;
  assert.equal(alive, true, 'client must stay connected while the broker pongs');

  client.stop();
  broker.server.close();
});

test('a silent broker triggers the keepalive watchdog', async () => {
  const broker = await createFakeBroker({ respondToPings: false });
  const client = makeClient(broker, { keepalive: 1, reconnectMinMs: 200, reconnectMaxMs: 200 });
  const subscribed = once(client, 'subscribed');
  const closed = once(client, 'close', 8000);
  client.start();
  await subscribed;

  await closed;
  assert.ok(broker.pingCount >= 1, 'pings must have been attempted before the watchdog fired');
  assert.equal(client.socket, null, 'the watchdog must tear the dead socket down');

  client.stop();
  broker.server.close();
});

/* ---------- resilience ---------- */

test('reconnects with backoff when the broker drops the connection', async () => {
  const broker = await createFakeBroker();
  const client = makeClient(broker, { keepalive: 30 });

  let subscribedCount = 0;
  client.on('subscribed', () => {
    subscribedCount += 1;
  });
  const first = once(client, 'subscribed');
  client.start();
  await first;

  broker.kill(0);

  const t0 = Date.now();
  while (subscribedCount < 2 && Date.now() < t0 + 4000) await sleep(25);
  assert.ok(subscribedCount >= 2, `expected a second subscription after reconnect, got ${subscribedCount}`);
  assert.ok(broker.accepted >= 2, 'broker must have accepted a new connection');

  client.stop();
  broker.server.close();
});

test('a rejected CONNACK surfaces an error and triggers retry', async () => {
  const broker = await createFakeBroker({ connackCode: 5 }); // "not authorized"
  const client = makeClient(broker, { keepalive: 30, reconnectMinMs: 20, reconnectMaxMs: 60 });

  let errors = 0;
  client.on('error', () => {
    errors += 1;
  });
  client.start();

  const t0 = Date.now();
  while (errors < 2 && Date.now() < t0 + 3000) await sleep(25);
  assert.ok(errors >= 2, 'client must keep retrying a rejected login');
  assert.ok(broker.accepted >= 2);

  client.stop();
  broker.server.close();
});