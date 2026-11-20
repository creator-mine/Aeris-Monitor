'use strict';

const http = require('http');
const crypto = require('crypto');
const { DeviceRegistry } = require('./registry');
const { AlertStore } = require('./alerts');
const { RuleStore } = require('./rules');
const { RulesEngine } = require('./rules_engine');
const { SettingsStore } = require('./settings');
const { MetricsCollector } = require('./metrics');
const { StabilityStore } = require('./stability');
const session = require('./session');
const { staticHandler } = require('./static');
const config = require('./config');

const VERSION = config.version;
const API = config.apiPrefix;
const PANEL_PATH = config.panel.path;

// Login brute-force guard (independent bucket, not user-tunable).
const RATE_LOGIN = 5;

/* ---------- helpers ---------- */

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
};

function sendJson(res, code, data) {
  const body = JSON.stringify(data);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    ...CORS_HEADERS,
    ...SECURITY_HEADERS,
  });
  res.end(body);
}

function sendText(res, code, text) {
  res.writeHead(code, { 'Content-Type': 'text/plain; charset=utf-8', ...CORS_HEADERS });
  res.end(text);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (chunk) => {
      raw += chunk;
      if (raw.length > 64 * 1024) {
        reject(new Error('body too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!raw) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

function parseUrl(req) {
  const [path, queryString] = req.url.split('?');
  const params = new URLSearchParams(queryString || '');
  return { path, params };
}

function clientIp(req) {
  return String(req.socket.remoteAddress || 'unknown');
}

/**
 * Assemble the full HTTP server (routes, stores, rate limiting, web panel).
 * The caller decides whether/what to listen on.
 */
function createServer(options = {}) {
  const telemetry = options.telemetry || null; // TelemetryStore (A2 ingest)
  const settings = new SettingsStore();
  const stability = new StabilityStore({ file: config.stability.file, maxEvents: config.stability.maxEvents });
  const registry = new DeviceRegistry({
    settings,
    onStatusChange: (device, previousStatus) => {
      if (previousStatus === device.status) return;
      stability.record(device.id, device.status);
    },
  });
  const alertStore = new AlertStore();
  const ruleStore = new RuleStore();

  // Give persisted devices a baseline in the stability journal.
  for (const d of registry.list()) {
    if (d.status === 'online') stability.ensureOnline(d.id);
    else stability.record(d.id, 'offline');
  }

  /* ---------- metrics ---------- */

  const requests = { count: 0, sumMs: 0 };
  const stats = { requests, devices: () => registry.stats() };
  const metrics = new MetricsCollector({
    file: config.metrics.file,
    intervalMs: config.metrics.intervalMs,
    hours: settings.metricsHours(),
  });
  metrics.start(stats);

  const metricsFlushTimer = setInterval(() => {
    metrics.hours = settings.metricsHours();
    metrics.flush();
    stability.flush();
  }, config.metrics.flushSeconds * 1000);
  metricsFlushTimer.unref();

  /* ---------- rate limiting ---------- */

  const buckets = new Map();
  let lastBucketPrune = 0;

  function take(ip, key, limit, windowMsOverride) {
    const now = Date.now();
    const windowMs = windowMsOverride || settings.rateLimit('window_ms') || config.rateLimit.windowMs;

    if (now - lastBucketPrune > windowMs) {
      lastBucketPrune = now;
      for (const [k, b] of buckets) {
        if (now - b.start > windowMs) buckets.delete(k);
      }
    }

    const b = buckets.get(key) || { count: 0, start: now };
    if (now - b.start > windowMs) {
      b.count = 0;
      b.start = now;
    }
    b.count += 1;
    buckets.set(key, b);
    const allowed = b.count <= limit;
    if (!allowed) console.log(`[ratelimit] blocked ${key} (${b.count}/${limit})`);
    return allowed;
  }

  function rateLimited(req, key, name) {
    const limit = settings.rateLimit(name);
    return !take(clientIp(req), key, limit != null ? limit : config.rateLimit[name]);
  }

  /* ---------- auth ---------- */

  const panelKey = () => settings.panelPassword();
  const panelRequest = (req) => session.sessionFromReq(req, panelKey()) > 0;

  /**
   * Parses `Authorization: Basic <base64(user:pass)>`.
   * Returns null for any other scheme or malformed input.
   */
  function basicCredentials(req) {
    const header = String(req.headers['authorization'] || '');
    if (!/^basic\s+/i.test(header)) return null;
    let decoded;
    try {
      decoded = Buffer.from(header.replace(/^basic\s+/i, '').trim(), 'base64').toString('utf8');
    } catch {
      return null;
    }
    const sep = decoded.indexOf(':');
    if (sep < 0) return null;
    return { user: decoded.slice(0, sep), pass: decoded.slice(sep + 1) };
  }

  function credentialMatches(creds, user, pass) {
    return (
      session.timingSafeEqualStr(creds.user, user) &&
      session.timingSafeEqualStr(creds.pass, pass)
    );
  }

  /**
   * Role of the caller: 'app' (MQTT_USER) or 'device' (MQTT_DEVICE_USER),
   * or null. There are no API tokens any more — the HTTP API reuses the
   * broker logins so a device/app only has one set of credentials.
   */
  function roleFor(req) {
    const creds = basicCredentials(req);
    if (!creds) return null;
    if (config.auth.appPassword && credentialMatches(creds, config.auth.appUser, config.auth.appPassword)) {
      return 'app';
    }
    if (
      config.auth.devicePassword &&
      credentialMatches(creds, config.auth.deviceUser, config.auth.devicePassword)
    ) {
      return 'device';
    }
    return null;
  }

  /** Devices-level auth: the device MQTT login (open when unset, legacy dev mode). */
  function deviceOk(req) {
    if (!config.auth.devicePassword) return true;
    return roleFor(req) === 'device';
  }

  /** Application reads: the app MQTT login (open when unset, legacy dev mode). */
  function appOk(req) {
    if (!config.auth.appPassword) return true;
    return roleFor(req) === 'app';
  }

  /** Panel/admin access: a valid panel session or the app login. */
  function adminOk(req) {
    if (panelRequest(req)) return true;
    return appOk(req);
  }

  /* ---------- device handlers ---------- */

  async function handleRegister(req, res) {
    if (!deviceOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'register:' + clientIp(req), 'register')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }

    if (!body.id) return sendJson(res, 400, { error: 'missing_id' });
    if (!body.ip) return sendJson(res, 400, { error: 'missing_ip' });

    const maxPerIp = settings.maxDevicesPerIp();
    if (maxPerIp > 0 && registry.countByIp(body.ip) >= maxPerIp) {
      return sendJson(res, 429, { error: 'too_many_devices_from_ip' });
    }

    const device = registry.register(body);
    if (!device) return sendJson(res, 400, { error: 'invalid_device' });

    sendJson(res, 200, { ok: true, device });
  }

  async function handleHeartbeat(req, res) {
    if (!deviceOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'heartbeat:' + clientIp(req), 'heartbeat')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    const { params } = parseUrl(req);
    let id = params.get('id') || req.headers['x-device-id'] || null;

    let body = null;
    if (!id) {
      try {
        body = await readBody(req);
        id = (body && body.id) || null;
      } catch (e) {
        /* invalid json body — ignore */
      }
    }

    if (!id) return sendJson(res, 400, { error: 'missing_id' });

    if (!body) {
      try {
        body = await readBody(req);
      } catch (e) {
        body = null;
      }
    }

    const device = registry.heartbeat(id, body);
    if (!device) return sendJson(res, 404, { ok: false, error: 'not_registered' });
    sendJson(res, 200, { ok: true, device });
  }

  function handleList(req, res) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'list:' + clientIp(req), 'read')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }
    const { params } = parseUrl(req);
    const online = params.get('online');
    const filter = {};
    if (online === 'true') filter.online = true;
    if (online === 'false') filter.online = false;
    sendJson(res, 200, registry.list(filter));
  }

  function handleGet(req, res, id) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'read:' + clientIp(req), 'read')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }
    const device = registry.get(id);
    if (!device) return sendJson(res, 404, { error: 'not_found' });
    sendJson(res, 200, device);
  }

  function handleRemove(req, res, id) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    const removed = registry.remove(id);
    if (!removed) return sendJson(res, 404, { error: 'not_found' });
    alertStore.removeByDevice(id);
    ruleStore.removeByDevice(id);
    stability.removeDevice(id);
    sendJson(res, 200, { ok: true });
  }

  /**
   * App-side rename: only the display name can be changed, so a user cannot
   * rewrite a device's IP/port through the public app API. The custom name is
   * preserved when the board re-registers after a reboot.
   */
  async function handleRename(req, res, id) {
    if (!appOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    let body;
    try {
      body = await readBody(req);
    } catch {
      return sendJson(res, 400, { error: 'invalid_json' });
    }
    if (!body || typeof body.name !== 'string') {
      return sendJson(res, 400, { error: 'invalid_name' });
    }

    const updated = registry.update(id, { name: body.name });
    if (updated instanceof Error) return sendJson(res, 400, { error: 'invalid_name' });
    if (!updated) return sendJson(res, 404, { error: 'not_found' });
    sendJson(res, 200, { ok: true, device: updated });
  }

  /* ---------- alerts handlers ---------- */

  async function handleAlertsList(req, res) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    const { params } = parseUrl(req);
    sendJson(res, 200, alertStore.list({ deviceId: params.get('device_id') }));
  }

  async function handleAlertCreate(req, res) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }

    const alert = alertStore.create(body);
    if (!alert) return sendJson(res, 400, { error: 'invalid_alert' });
    sendJson(res, 200, alert);
  }

  async function handleAlertUpdate(req, res, id) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }

    const alert = alertStore.update(id, body);
    if (!alert) {
      const exists = alertStore.get(id);
      return sendJson(res, exists ? 400 : 404, { error: exists ? 'invalid_alert' : 'not_found' });
    }
    sendJson(res, 200, alert);
  }

  function handleAlertDelete(req, res, id) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    if (!alertStore.remove(id)) return sendJson(res, 404, { error: 'not_found' });
    sendJson(res, 200, { ok: true });
  }

  /* ---------- smart-home rule handlers ---------- */

  async function handleRulesList(req, res) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    const { params } = parseUrl(req);
    sendJson(res, 200, ruleStore.list({ deviceId: params.get('device_id') }));
  }

  async function handleRuleCreate(req, res) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }

    const rule = ruleStore.create(body);
    if (!rule) return sendJson(res, 400, { error: 'invalid_rule' });
    sendJson(res, 200, rule);
  }

  async function handleRuleUpdate(req, res, id) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }

    const rule = ruleStore.update(id, body);
    if (!rule) {
      const exists = ruleStore.get(id);
      return sendJson(res, exists ? 400 : 404, { error: exists ? 'invalid_rule' : 'not_found' });
    }
    sendJson(res, 200, rule);
  }

  function handleRuleDelete(req, res, id) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    if (!ruleStore.remove(id)) return sendJson(res, 404, { error: 'not_found' });
    sendJson(res, 200, { ok: true });
  }

  /* ---------- web panel ---------- */

  const panelStatic = staticHandler(config.panel.staticDir);

  function panelEnabled() {
    return settings.panelEnabled();
  }

  async function handlePanelLogin(req, res) {
    if (!panelEnabled()) return sendJson(res, 503, { error: 'panel_disabled' });
    if (!take(clientIp(req), 'panellogin:' + clientIp(req), RATE_LOGIN, 60_000)) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }

    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }

    const password = String(body.password || '');
    if (!session.timingSafeEqualStr(password, settings.panelPassword())) {
      return sendJson(res, 401, { error: 'unauthorized' });
    }

    const secure = String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim() === 'https';
    session.setCookie(res, Date.now() + settings.sessionTtlMs(), { secure, keyMaterial: panelKey() });
    sendJson(res, 200, { ok: true });
  }

  function handlePanelLogout(req, res) {
    session.clearCookie(res);
    sendJson(res, 200, { ok: true });
  }

  function handlePanelSession(req, res) {
    if (!panelEnabled()) return sendJson(res, 503, { error: 'panel_disabled' });
    if (!panelRequest(req)) return sendJson(res, 401, { error: 'unauthorized' });
    sendJson(res, 200, {
      ok: true,
      version: VERSION,
      path: PANEL_PATH,
      panel_enabled: true,
    });
  }

  function handlePanelSystem(req, res) {
    metrics.sample(stats); // refresh the latest bucket on demand
    const s = metrics.last();
    const alerts = alertStore.list();
    const rules = ruleStore.list();
    const uptimeSec = process.uptime();
    sendJson(res, 200, {
      ok: true,
      version: VERSION,
      node: process.version,
      uptime: uptimeSec,
      uptime_sec: uptimeSec,
      cpu_percent: s ? s.cpu : null,
      mem_percent: s ? s.mem : null,
      system: s
        ? {
            t: s.t,
            cpu: s.cpu,
            mem: s.mem,
            load1: s.load1,
            net_rx_kb_s: s.net_rx_kb_s,
            net_tx_kb_s: s.net_tx_kb_s,
            req_min: s.req_min,
            avg_ms: s.avg_ms,
          }
        : null,
      devices: registry.stats(),
      alerts: { total: alerts.length, active: alerts.filter((a) => a.is_active).length },
      rules: { total: rules.length, enabled: rules.filter((r) => r.enabled).length },
      metrics_window_hours: settings.metricsHours(),
      panel: { path: PANEL_PATH, enabled: panelEnabled() },
    });
  }

  function handlePanelHistory(req, res) {
    const { params } = parseUrl(req);
    const data = metrics.history(Number(params.get('points')) || 120);
    const timestamps = data.perf.map((p) => p.t);
    const metricsView = {
      cpu: data.perf.map((p) => p.cpu),
      mem: data.perf.map((p) => p.mem),
      load: data.perf.map((p) => p.load1),
      net_rx_kb_s: data.perf.map((p) => p.net_rx_kb_s),
      net_tx_kb_s: data.perf.map((p) => p.net_tx_kb_s),
      req_min: data.perf.map((p) => p.req_min),
      avg_ms: data.perf.map((p) => p.avg_ms),
      online: data.online.map((p) => p.online),
    };
    sendJson(res, 200, {
      timestamps,
      metrics: metricsView,
      perf: data.perf,
      online: data.online,
    });
  }

  function enrichDevice(d) {
    const alerts = alertStore.list({ deviceId: d.id });
    const rules = ruleStore.list({ deviceId: d.id });
    return {
      ...d,
      uptime24: stability.uptime24h(d.id, d.status),
      alerts: alerts.length,
      rules: rules.length,
    };
  }

  function handlePanelDevices(req, res) {
    const { params } = parseUrl(req);
    const online = params.get('online');
    const filter = {};
    if (online === 'true') filter.online = true;
    if (online === 'false') filter.online = false;

    const q = (params.get('q') || '').toLowerCase();
    const devices = registry
      .list(filter)
      .filter(
        (d) =>
          !q ||
          d.id.toLowerCase().includes(q) ||
          String(d.name || '').toLowerCase().includes(q) ||
          String(d.type || '').toLowerCase().includes(q),
      )
      .map(enrichDevice);
    sendJson(res, 200, devices);
  }

  function handlePanelDeviceGet(req, res, id) {
    const d = registry.get(id);
    if (!d) return sendJson(res, 404, { error: 'not_found' });
    const uptime24 = stability.uptime24h(d.id, d.status);
    const uptime7d = stability.uptime7d(d.id, d.status);
    sendJson(res, 200, {
      device: { ...d, uptime24, uptime7d },
      stability: {
        events: stability.events(d.id),
        uptime24,
        uptime7d,
        current_status: d.status,
      },
      alerts: alertStore.list({ deviceId: d.id }),
      rules: ruleStore.list({ deviceId: d.id }),
    });
  }

  async function handlePanelDeviceCreate(req, res) {
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }
    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }
    const device = registry.register(body);
    if (!device) return sendJson(res, 400, { error: 'invalid_device' });
    stability.ensureOnline(device.id);
    sendJson(res, 200, { ok: true, device: enrichDevice(device) });
  }

  async function handlePanelDeviceUpdate(req, res, id) {
    if (rateLimited(req, 'write:' + clientIp(req), 'write')) {
      return sendJson(res, 429, { error: 'rate_limited' });
    }
    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }
    if (!registry.get(id)) return sendJson(res, 404, { error: 'not_found' });
    const updated = registry.update(id, body);
    if (updated instanceof Error) return sendJson(res, 400, { error: 'invalid_device' });
    if (!updated) return sendJson(res, 404, { error: 'not_found' });
    sendJson(res, 200, { ok: true, device: enrichDevice(updated) });
  }

  function handlePanelDeviceDelete(req, res, id) {
    if (!registry.remove(id)) return sendJson(res, 404, { error: 'not_found' });
    alertStore.removeByDevice(id);
    ruleStore.removeByDevice(id);
    stability.removeDevice(id);
    sendJson(res, 200, { ok: true });
  }

  function handlePanelSettingsGet(req, res) {
    const limits = {};
    for (const name of ['window_ms', 'register', 'heartbeat', 'write', 'read']) {
      limits[name] = settings.rateLimit(name);
    }
    sendJson(res, 200, {
      ok: true,
      version: VERSION,
      api_prefix: API,
      panel: { path: PANEL_PATH, enabled: panelEnabled() },
      stale_ms: settings.staleMs(),
      metrics_hours: settings.metricsHours(),
      max_devices_per_ip: settings.maxDevicesPerIp(),
      session_ttl_ms: settings.sessionTtlMs(),
      rate_limits: limits,
    });
  }

  async function handlePanelSettingsPut(req, res) {
    let body;
    try {
      body = await readBody(req);
    } catch (e) {
      return sendJson(res, 400, { error: 'invalid_json' });
    }
    const result = settings.update(body);
    if (!result.ok) return sendJson(res, 400, { error: result.error });
    metrics.hours = settings.metricsHours();
    handlePanelSettingsGet(req, res);
  }

  function handlePanelRestart(req, res) {
    sendJson(res, 200, { ok: true });
    setTimeout(() => {
      console.log('[panel] restart requested');
      registry.flush();
      stability.flush();
      metrics.flush();
      process.exit(0);
    }, 250);
  }

  async function handlePanelApi(req, res, subPath) {
    const method = req.method;
    const [head, tail] = subPath.split('/');

    if (head === 'auth') {
      if (tail === 'login' && method === 'POST') return handlePanelLogin(req, res);
      if (tail === 'logout' && method === 'POST') return handlePanelLogout(req, res);
      if (tail === 'session' && method === 'GET') return handlePanelSession(req, res);
      return sendJson(res, 404, { error: 'not_found' });
    }

    // Convenience alias: GET /panel/api/session
    if (head === 'session' && !tail && method === 'GET') return handlePanelSession(req, res);

    // Everything below requires a live panel session (or api token).
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });

    if (head === 'system') {
      if (tail === 'history' && method === 'GET') return handlePanelHistory(req, res);
      if (!tail && method === 'GET') return handlePanelSystem(req, res);
      return sendJson(res, 404, { error: 'not_found' });
    }

    if (head === 'settings') {
      if (!tail && method === 'GET') return handlePanelSettingsGet(req, res);
      if (!tail && method === 'PUT') return handlePanelSettingsPut(req, res);
      return sendJson(res, 404, { error: 'not_found' });
    }

    if (head === 'restart' && !tail && method === 'POST') return handlePanelRestart(req, res);

    if (head === 'devices') {
      if (!tail && method === 'GET') return handlePanelDevices(req, res);
      if (!tail && method === 'POST') return handlePanelDeviceCreate(req, res);
      if (tail) {
        let id;
        try {
          id = decodeURIComponent(tail);
        } catch {
          return sendJson(res, 400, { error: 'bad_device_id' });
        }
        if (method === 'GET') return handlePanelDeviceGet(req, res, id);
        if (method === 'PUT') return handlePanelDeviceUpdate(req, res, id);
        if (method === 'DELETE') return handlePanelDeviceDelete(req, res, id);
      }
      return sendJson(res, 404, { error: 'not_found' });
    }

    return sendJson(res, 404, { error: 'not_found' });
  }

  /* ---------- live stream (SSE) ---------- */

  const sseClients = new Set();
  const SSE_MAX_CLIENTS = 16;

  function sseWrite(res, event, data) {
    if (res.writableEnded || res.destroyed) return;
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  }

  function broadcastSSE(event, data) {
    const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
    for (const res of sseClients) {
      if (!res.writableEnded && !res.destroyed) res.write(payload);
    }
  }

  function handleStream(req, res) {
    // The stream exposes live telemetry, device state and rule events, so it
    // requires the panel session or the app login (HTTP Basic).
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    if (sseClients.size >= SSE_MAX_CLIENTS) {
      return sendJson(res, 503, { error: 'stream_busy' });
    }
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
      'Access-Control-Allow-Origin': '*',
      ...SECURITY_HEADERS,
    });
    res.write(': connected\n\n');

    sseClients.add(res);
    sseWrite(res, 'hello', {
      version: VERSION,
      ts: Date.now(),
      telemetry: telemetry ? telemetry.latestValues() : null,
      devices: registry.stats(),
    });

    const heartbeat = setInterval(() => {
      if (!res.writableEnded && !res.destroyed) res.write(': ping\n\n');
    }, 25_000);
    heartbeat.unref();

    res.on('close', () => {
      clearInterval(heartbeat);
      sseClients.delete(res);
    });
  }

  function handleSensorLatest(req, res) {
    sendJson(res, 200, {
      ok: true,
      version: VERSION,
      devices: telemetry ? telemetry.latestValues() : null,
    });
  }

  function handleSensorHistory(req, res, deviceId, sensor) {
    const { params } = parseUrl(req);
    const to = Number(params.get('to')) || Date.now();
    const from = Number(params.get('from')) || to - 24 * 3600 * 1000;
    const points = Number(params.get('points')) || 120;
    const series = telemetry ? telemetry.query(deviceId, sensor, { from, to, points }) : [];
    sendJson(res, 200, {
      ok: true,
      deviceId,
      sensor,
      from,
      to,
      points: series.length,
      series,
    });
  }

  /* ---------- rules engine ---------- */

  const rulesEngine = new RulesEngine({ ruleStore, registry, telemetry });
  rulesEngine
    .setPublish((topic, payload) => {
      if (options.mqtt && typeof options.mqtt.publish === 'function') {
        options.mqtt.publish(topic, payload);
        return true;
      }
      return false;
    })
    .on('fire', (info) => broadcastSSE('rule', info))
    .start();

  function publishCommand(deviceId, payload) {
    const id = String(deviceId);
    if (id === '.' || id === '..') return false;
    if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(id)) return false;
    if (!options.mqtt || typeof options.mqtt.publish !== 'function') return false;
    options.mqtt.publish('iot/' + deviceId + '/commands', String(payload));
    broadcastSSE('cmd', { deviceId, command: String(payload), ts: Date.now() });
    return true;
  }

  /* ---------- remote Wi-Fi switch (two-phase, opt-in) ---------- */

  const wifiRequests = new Map();

  function wifiKey(deviceId, requestId) {
    return String(deviceId) + '|' + String(requestId);
  }

  function cleanupWifiRequests() {
    const now = Date.now();
    for (const [key, value] of wifiRequests) {
      if (value.expiresAt && value.expiresAt < now &&
          (value.status === 'prepared' || value.status === 'committing')) {
        value.status = 'expired';
      }
      if (value.updatedAt && value.updatedAt < now - 30 * 60 * 1000) {
        wifiRequests.delete(key);
      }
    }
  }

  async function handleWifiPrepare(req, res, deviceId) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    let body;
    try {
      body = await readBody(req);
    } catch {
      return sendJson(res, 400, { error: 'invalid_json' });
    }
    const networkId = Number(body.network_id ?? body.id);
    if (!Number.isInteger(networkId) || networkId <= 0 || networkId > 255) {
      return sendJson(res, 400, { error: 'bad_network_id' });
    }
    const requestId = String(body.request_id || crypto.randomUUID());
    const payload = JSON.stringify({
      type: 'command',
      command: 'wifi_prepare',
      request_id: requestId,
      id: networkId,
    });
    if (!publishCommand(deviceId, payload)) {
      return sendJson(res, 503, { error: 'mqtt_off' });
    }
    cleanupWifiRequests();
    wifiRequests.set(wifiKey(deviceId, requestId), {
      deviceId: String(deviceId),
      requestId,
      networkId,
      status: 'prepared',
      createdAt: Date.now(),
      updatedAt: Date.now(),
      expiresAt: Date.now() + 120000,
    });
    return sendJson(res, 200, {
      ok: true,
      deviceId: String(deviceId),
      request_id: requestId,
      status: 'prepared',
      expires_in: 120,
    });
  }

  async function handleWifiCommit(req, res, deviceId) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    let body;
    try {
      body = await readBody(req);
    } catch {
      return sendJson(res, 400, { error: 'invalid_json' });
    }
    const requestId = String(body.request_id || '');
    if (!requestId) return sendJson(res, 400, { error: 'missing_request_id' });
    cleanupWifiRequests();
    const pending = wifiRequests.get(wifiKey(deviceId, requestId));
    if (!pending) return sendJson(res, 404, { error: 'not_found' });
    if (pending.status === 'expired') {
      return sendJson(res, 410, { error: 'expired' });
    }
    if (pending.status !== 'prepared') {
      return sendJson(res, 409, { error: 'bad_state', status: pending.status });
    }
    const payload = JSON.stringify({
      type: 'command',
      command: 'wifi_commit',
      request_id: requestId,
    });
    if (!publishCommand(deviceId, payload)) {
      return sendJson(res, 503, { error: 'mqtt_off' });
    }
    pending.status = 'committing';
    pending.updatedAt = Date.now();
    pending.expiresAt = Date.now() + 90000;
    return sendJson(res, 200, { ok: true, request_id: requestId, status: 'committing' });
  }

  function handleWifiResult(req, res, deviceId) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    cleanupWifiRequests();
    let requestId = null;
    try {
      requestId = new URL(req.url, 'http://localhost').searchParams.get('request_id');
    } catch {
      requestId = null;
    }
    if (requestId) {
      const item = wifiRequests.get(wifiKey(deviceId, requestId));
      if (!item) return sendJson(res, 404, { error: 'not_found' });
      return sendJson(res, 200, item);
    }
    const items = [];
    for (const item of wifiRequests.values()) {
      if (item.deviceId === String(deviceId)) items.push(item);
    }
    return sendJson(res, 200, { requests: items });
  }

  const wifiListWaiters = new Map();

  function handleWifiList(req, res, deviceId) {
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    const requestId = crypto.randomUUID();
    const payload = JSON.stringify({
      type: 'command',
      command: 'wifi_list',
      request_id: requestId,
    });
    if (!publishCommand(deviceId, payload)) {
      return sendJson(res, 503, { error: 'mqtt_off' });
    }
    const key = wifiKey(deviceId, requestId);
    const timer = setTimeout(() => {
      if (wifiListWaiters.has(key)) {
        wifiListWaiters.delete(key);
        sendJson(res, 504, { error: 'device_timeout' });
      }
    }, 8000);
    wifiListWaiters.set(key, { res, timer, requestId });
  }

  async function handleDeviceCommand(req, res, deviceId) {
    const id = String(deviceId);
    if (id === '.' || id === '..' || !/^[A-Za-z0-9_.:-]{1,64}$/.test(id)) {
      return sendJson(res, 400, { error: 'invalid_device_id' });
    }
    if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
    let body;
    try {
      body = await readBody(req);
    } catch {
      return sendJson(res, 400, { error: 'invalid_json' });
    }
    const command = String(body.command ?? body.action ?? '').trim().slice(0, 512);
    if (!command) return sendJson(res, 400, { error: 'missing_command' });
    if (!publishCommand(deviceId, command)) return sendJson(res, 503, { error: 'mqtt_off' });
    return sendJson(res, 200, { ok: true, deviceId, command, mqtt: true });
  }

  /*
   * Live data path (A2/A3/A4):
   *   metric -> TelemetryStore.append + RulesEngine + SSE 'metric'
   *   status -> RulesEngine + SSE 'status'
   */
  if (options.mqtt) {
    options.mqtt.on('metric', (m) => {
      if (telemetry) telemetry.append(m);
      rulesEngine.onMetric(m);
      broadcastSSE('metric', m);
    });
    options.mqtt.on('status', (s) => {
      rulesEngine.onStatus(s);
      broadcastSSE('status', s);
    });
    options.mqtt.on('wifi_result', (r) => {
      if (r.requestId && r.status === 'list') {
        const waiter = wifiListWaiters.get(wifiKey(r.deviceId, r.requestId));
        if (waiter) {
          clearTimeout(waiter.timer);
          wifiListWaiters.delete(wifiKey(r.deviceId, r.requestId));
          sendJson(waiter.res, 200, r.data || {});
        }
      }
      if (r.requestId) {
        const item = wifiRequests.get(wifiKey(r.deviceId, r.requestId));
        if (item) {
          item.status = r.status === 'ok' ? 'ok' : (r.status || 'error');
          item.error = r.error || null;
          item.ssid = r.ssid || null;
          item.updatedAt = Date.now();
          item.expiresAt = Date.now() + 30 * 60 * 1000;
        }
      }
      broadcastSSE('wifi', r);
    });
  }

  /* ---------- router ---------- */

  const server = http.createServer((req, res) => {
    handleRequest(req, res).catch((err) => {
      console.error(`[err] ${req.method} ${req.url}:`, err);
      if (res.headersSent) return res.destroy();
      sendJson(res, 500, { error: 'internal_error' });
    });
  });

  async function handleRequest(req, res) {
    const started = Date.now();
    const originalEnd = res.end.bind(res);
    let logged = false;
    res.end = (...args) => {
      if (!logged) {
        logged = true;
        requests.count += 1;
        requests.sumMs += Date.now() - started;
        console.log(`[req] ${req.method} ${req.url} -> ${res.statusCode} ${Date.now() - started}ms`);
      }
      return originalEnd(...args);
    };

    const { path } = parseUrl(req);

    if (req.method === 'OPTIONS') {
      res.writeHead(204, CORS_HEADERS);
      return res.end();
    }

    // Simple root info
    if (path === '/' || path === '') {
      return sendText(res, 200, `Aeris Monitor - Signaling Server v${VERSION}\nAPI: ${API}\nPanel: ${PANEL_PATH}\n`);
    }

    if (req.method === 'GET' && path === API + '/health') {
      const { total, online, offline } = registry.stats();
      return sendJson(res, 200, {
        ok: true,
        version: VERSION,
        uptime: process.uptime(),
        devices: { total, online, offline },
        alerts: alertStore.list().length,
        rules: ruleStore.list().length,
        panel_session: panelRequest(req),
      });
    }

    if (req.method === 'GET' && path === API + '/meta') {
      return sendJson(res, 200, {
        version: VERSION,
        stale_ms: settings.staleMs(),
        rate_limits: {
          window_ms: settings.rateLimit('window_ms'),
          register: settings.rateLimit('register'),
          heartbeat: settings.rateLimit('heartbeat'),
          write: settings.rateLimit('write'),
          read: settings.rateLimit('read'),
        },
        auth_enabled: config.auth.enabled,
        auth_mode: 'basic',
        max_devices_per_ip: settings.maxDevicesPerIp(),
      });
    }

    if (req.method === 'GET' && path === API + '/stream') {
      return handleStream(req, res);
    }

    if (req.method === 'GET' && path === API + '/sensors/latest') {
      if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
      return handleSensorLatest(req, res);
    }

    // /api/v1/sensors/:deviceSensors/:sensor/history
    const sensorHistoryMatch = path.match(new RegExp('^' + API + '/sensors/([^/]+)/([^/]+)/history$'));
    if (sensorHistoryMatch) {
      if (req.method !== 'GET') return sendJson(res, 405, { error: 'method_not_allowed' });
      if (!adminOk(req)) return sendJson(res, 401, { error: 'unauthorized' });
      let deviceId;
      let sensor;
      try {
        deviceId = decodeURIComponent(sensorHistoryMatch[1]);
        sensor = decodeURIComponent(sensorHistoryMatch[2]);
      } catch {
        sendJson(res, 400, { error: 'bad_sensor_ref' });
        return;
      }
      return handleSensorHistory(req, res, deviceId, sensor);
    }

    if (req.method === 'POST' && path === API + '/devices/register') {
      return handleRegister(req, res);
    }

    if (req.method === 'POST' && path === API + '/devices/heartbeat') {
      return handleHeartbeat(req, res);
    }

    if (req.method === 'GET' && path === API + '/devices') {
      return handleList(req, res);
    }

    // Alerts collection
    if (path === API + '/alerts') {
      if (req.method === 'GET') return handleAlertsList(req, res);
      if (req.method === 'POST') return handleAlertCreate(req, res);
    }

    // /api/v1/alerts/:id
    const alertMatch = path.match(new RegExp('^' + API + '/alerts/([^/]+)$'));
    if (alertMatch) {
      let id;
      try {
        id = decodeURIComponent(alertMatch[1]);
      } catch {
        sendJson(res, 400, { error: 'bad_alert_id' });
        return;
      }
      if (req.method === 'PUT') return handleAlertUpdate(req, res, id);
      if (req.method === 'DELETE') return handleAlertDelete(req, res, id);
    }

    // Smart-home rules collection
    if (path === API + '/rules') {
      if (req.method === 'GET') return handleRulesList(req, res);
      if (req.method === 'POST') return handleRuleCreate(req, res);
    }

    // /api/v1/rules/:id
    const ruleMatch = path.match(new RegExp('^' + API + '/rules/([^/]+)$'));
    if (ruleMatch) {
      let id;
      try {
        id = decodeURIComponent(ruleMatch[1]);
      } catch {
        sendJson(res, 400, { error: 'bad_rule_id' });
        return;
      }
      if (req.method === 'PUT') return handleRuleUpdate(req, res, id);
      if (req.method === 'DELETE') return handleRuleDelete(req, res, id);
    }

    // /api/v1/devices/:id/wifi/list | prepare | commit | result
    const wifiListMatch = path.match(new RegExp('^' + API + '/devices/([^/]+)/wifi/list$'));
    if (wifiListMatch) {
      if (req.method !== 'GET') return sendJson(res, 405, { error: 'method_not_allowed' });
      let id;
      try {
        id = decodeURIComponent(wifiListMatch[1]);
      } catch {
        return sendJson(res, 400, { error: 'bad_device_id' });
      }
      return handleWifiList(req, res, id);
    }

    const wifiPrepareMatch = path.match(new RegExp('^' + API + '/devices/([^/]+)/wifi/prepare$'));
    if (wifiPrepareMatch) {
      if (req.method !== 'POST') return sendJson(res, 405, { error: 'method_not_allowed' });
      let id;
      try {
        id = decodeURIComponent(wifiPrepareMatch[1]);
      } catch {
        return sendJson(res, 400, { error: 'bad_device_id' });
      }
      return handleWifiPrepare(req, res, id);
    }

    const wifiCommitMatch = path.match(new RegExp('^' + API + '/devices/([^/]+)/wifi/commit$'));
    if (wifiCommitMatch) {
      if (req.method !== 'POST') return sendJson(res, 405, { error: 'method_not_allowed' });
      let id;
      try {
        id = decodeURIComponent(wifiCommitMatch[1]);
      } catch {
        return sendJson(res, 400, { error: 'bad_device_id' });
      }
      return handleWifiCommit(req, res, id);
    }

    const wifiResultMatch = path.match(new RegExp('^' + API + '/devices/([^/]+)/wifi/result$'));
    if (wifiResultMatch) {
      if (req.method !== 'GET') return sendJson(res, 405, { error: 'method_not_allowed' });
      let id;
      try {
        id = decodeURIComponent(wifiResultMatch[1]);
      } catch {
        return sendJson(res, 400, { error: 'bad_device_id' });
      }
      return handleWifiResult(req, res, id);
    }

    // /api/v1/devices/:id/command
    const deviceCommandMatch = path.match(new RegExp('^' + API + '/devices/([^/]+)/command$'));
    if (deviceCommandMatch) {
      if (req.method !== 'POST') return sendJson(res, 405, { error: 'method_not_allowed' });
      let id;
      try {
        id = decodeURIComponent(deviceCommandMatch[1]);
      } catch {
        sendJson(res, 400, { error: 'bad_device_id' });
        return;
      }
      return handleDeviceCommand(req, res, id);
    }

    // /api/v1/devices/:id
    const deviceMatch = path.match(new RegExp('^' + API + '/devices/([^/]+)$'));
    if (deviceMatch) {
      let id;
      try {
        id = decodeURIComponent(deviceMatch[1]);
      } catch {
        sendJson(res, 400, { error: 'bad_device_id' });
        return;
      }
      if (req.method === 'GET') return handleGet(req, res, id);
      if (req.method === 'PUT' || req.method === 'PATCH') return handleRename(req, res, id);
      if (req.method === 'DELETE') return handleRemove(req, res, id);
    }

    /* ---------- web panel ---------- */

    if (path === PANEL_PATH) {
      res.writeHead(301, { Location: PANEL_PATH + '/', ...SECURITY_HEADERS });
      return res.end();
    }

    if (path.startsWith(PANEL_PATH + '/api/')) {
      const subPath = path.slice((PANEL_PATH + '/api/').length);
      return handlePanelApi(req, res, subPath);
    }

    if (path.startsWith(PANEL_PATH + '/')) {
      const handled = panelStatic(req, res, path.slice(PANEL_PATH.length));
      if (handled) return;
      return sendJson(res, 404, { error: 'not_found' });
    }

    sendJson(res, 404, { error: 'not_found' });
  }

  return {
    server,
    registry,
    alertStore,
    ruleStore,
    rulesEngine,
    settings,
    metrics,
    stability,
    telemetry,
    mqtt: options.mqtt || null,
    publishCommand,
  };
}

module.exports = { createServer };