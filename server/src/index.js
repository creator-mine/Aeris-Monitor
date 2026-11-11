'use strict';

const { createServer } = require('./app');
const config = require('./config');

const API = config.apiPrefix;
const PANEL = config.panel.path;

const PORT = config.server.port;
const HOST = config.server.host;

let telemetry = null;
let mqtt = null;

// A2: MQTT bridge (opt-in via MQTT_ENABLED=1, credentials from the env file).
if (config.mqtt.enabled) {
  const { TelemetryStore } = require('./ingest');
  const { createMqttClient } = require('./mqtt_client');

  telemetry = new TelemetryStore({
    dir: config.ingest.dir,
    latestFile: config.ingest.latestFile,
    flushSeconds: config.ingest.flushSeconds,
  });
  mqtt = createMqttClient({
    host: config.mqtt.host,
    port: config.mqtt.port,
    user: config.mqtt.user,
    password: config.mqtt.password,
    clientId: config.mqtt.clientId,
    topic: config.mqtt.topic,
    keepalive: config.mqtt.keepalive,
  });
  mqtt.on('error', (err) => console.error(`[mqtt] ${err.message}`));
  mqtt.on('subscribed', () => console.log(`[mqtt] subscribed to '${config.mqtt.topic}'`));
  mqtt.start();
}

const app = createServer({ telemetry, mqtt });
const server = app.server;

server.listen(PORT, HOST, () => {
  console.log(`[signaling] v${config.version} http://${HOST}:${PORT}`);
  console.log(`[signaling] API: ${API}/devices, ${API}/devices/register, ${API}/devices/heartbeat`);
  console.log(`[signaling] Panel: ${PANEL} (${app.settings.panelEnabled() ? 'enabled' : 'disabled — set PANEL_PASSWORD'})`);
  console.log(`[signaling] auth_enabled=${app.settings.apiToken().length > 0}`);
  console.log(`[signaling] mqtt=${config.mqtt.enabled ? `on (${config.mqtt.user}@${config.mqtt.host}:${config.mqtt.port} -> '${config.mqtt.topic}')` : 'off'}`);
  console.log(`[signaling] ingest=${telemetry ? telemetry.dir : 'off'}`);
});

// graceful shutdown
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    console.log(`\n[signaling] shutting down (${sig})`);
    if (mqtt) mqtt.stop();
    app.rulesEngine && app.rulesEngine.stop();
    if (telemetry) telemetry.close();
    app.registry.flush();
    app.stability && app.stability.flush();
    app.metrics && app.metrics.flush();
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}