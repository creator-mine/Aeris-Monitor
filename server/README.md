# IoT SIGNALING SERVER

Р›С‘РіРєРёР№ REST API / СЂРµРµСЃС‚СЂ СѓСЃС‚СЂРѕР№СЃС‚РІ РґР»СЏ Aeris Monitor.
РЎРѕРµРґРёРЅСЏРµС‚ РїСЂРёР»РѕР¶РµРЅРёРµ Рё ESP32-СѓСЃС‚СЂРѕР№СЃС‚РІР°: СЂРµРіРёСЃС‚СЂР°С†РёСЏ, heartbeat, СЃРїРёСЃРѕРє СѓСЃС‚СЂРѕР№СЃС‚РІ,
Р°Р»РµСЂС‚С‹ Рё РїСЂР°РІРёР»Р° СѓРјРЅРѕРіРѕ РґРѕРјР°. **РўРµР»РµРјРµС‚СЂРёСЋ РЅРµ С…СЂР°РЅРёС‚** вЂ” С‚РѕР»СЊРєРѕ СЂРµРµСЃС‚СЂ Рё РїСЂР°РІРёР»Р°.

РќРѕР»СЊ РІРЅРµС€РЅРёС… Р·Р°РІРёСЃРёРјРѕСЃС‚РµР№ (С‚РѕР»СЊРєРѕ РІСЃС‚СЂРѕРµРЅРЅС‹Рµ РјРѕРґСѓР»Рё Node.js в‰Ґ 18).
РЎ РІРµСЂСЃРёРё 0.4 РїРѕСЃС‚Р°РІР»СЏРµС‚СЃСЏ **РІРµР±-РїР°РЅРµР»СЊ** (`/panel`, Vue 3, СЃС‚РёР»СЊ 3X-UI):
РґР°С€Р±РѕСЂРґ СЃ РіСЂР°С„РёРєР°РјРё РїСЂРѕРёР·РІРѕРґРёС‚РµР»СЊРЅРѕСЃС‚Рё, РєР°СЂС‚РѕС‡РєРё СѓСЃС‚СЂРѕР№СЃС‚РІ СЃ Р°РїС‚Р°Р№РјРѕРј,
CRUD СѓСЃС‚СЂРѕР№СЃС‚РІ/Р°Р»РµСЂС‚РѕРІ/РїСЂР°РІРёР» Рё РЅР°СЃС‚СЂРѕР№РєРё СЃРµСЂРІРµСЂР° РІ СЂР°РЅС‚Р°Р№РјРµ.

## РЎРѕСЃС‚Р°РІ

| Р¤Р°Р№Р» | РќР°Р·РЅР°С‡РµРЅРёРµ |
|---|---|
| `src/index.js` | РўРѕС‡РєР° РІС…РѕРґР°: HTTP-СЃРµСЂРІРµСЂ + graceful shutdown |
| `src/app.js` | РњР°СЂС€СЂСѓС‚С‹, rate-limit, CORS, auth, panel API + СЃС‚Р°С‚РёРєР° `/panel` |
| `src/registry.js` | Р РµРµСЃС‚СЂ СѓСЃС‚СЂРѕР№СЃС‚РІ (СЃС‚Р°С‚СѓСЃС‹, stale-С‚Р°Р№РјР°СѓС‚, Р»РёРјРёС‚С‹ РїРѕ IP) |
| `src/rules.js` | РџСЂР°РІРёР»Р° СѓРјРЅРѕРіРѕ РґРѕРјР° (CRUD + РїРµСЂСЃРёСЃС‚) |
| `src/alerts.js` | CRUD Р°Р»РµСЂС‚РѕРІ |
| `src/metrics.js` | РњРµС‚СЂРёРєРё СЃРµСЂРІРµСЂР° (CPU/MEM/load/СЃРµС‚СЊ/req/latency, РїРµСЂСЃРёСЃС‚) |
| `src/stability.js` | Р–СѓСЂРЅР°Р» СЃС‚Р°С‚СѓСЃРѕРІ СѓСЃС‚СЂРѕР№СЃС‚РІ + Р°РїС‚Р°Р№Рј 24С‡/7Рґ |
| `src/settings.js` | РџРµСЂРµРѕРїСЂРµРґРµР»РµРЅРёРµ РЅР°СЃС‚СЂРѕРµРє РІ СЂР°РЅС‚Р°Р№РјРµ (РІР°Р»РёРґР°С†РёСЏ, РїРµСЂСЃРёСЃС‚) |
| `src/session.js` | HMAC-СЃРµСЃСЃРёРё РїР°РЅРµР»Рё (HttpOnly cookie) |
| `src/persist.js` | РђС‚РѕРјР°СЂРЅР°СЏ Р·Р°РїРёСЃСЊ JSON РІ С„Р°Р№Р» |
| `src/config.js` | Р’СЃСЏ РєРѕРЅС„РёРіСѓСЂР°С†РёСЏ С‡РµСЂРµР· env |
| `web/` | Р¤СЂРѕРЅС‚РµРЅРґ РїР°РЅРµР»Рё (Vue 3 + Vite + Element Plus + uPlot); `web/dist` СЃРѕР±РёСЂР°РµС‚СЃСЏ РІ РѕР±СЂР°Р· |

## Р—Р°РїСѓСЃРє

```bash
node src/index.js
```

Р—РґРѕСЂРѕРІСЊРµ: `GET /api/v1/health`. РўРµСЃС‚С‹: `npm test` (= `node --test test/*.test.js`), 88 С‚РµСЃС‚РѕРІ.
РЎР±РѕСЂРєР° С„СЂРѕРЅС‚РµРЅРґР°: `npm --prefix web install && npm --prefix web run build` (dist СѓР¶Рµ РІ РѕР±СЂР°Р·/СЂРµРїРѕ).

## РљРѕРЅС„РёРіСѓСЂР°С†РёСЏ (env)

| РџРµСЂРµРјРµРЅРЅР°СЏ | РџРѕ СѓРјРѕР»С‡Р°РЅРёСЋ | РћРїРёСЃР°РЅРёРµ |
|---|---|---|
| `PORT` | `3000` | РџРѕСЂС‚ HTTP |
| `HOST` | `127.0.0.1` | РђРґСЂРµСЃ (РЅР°СЂСѓР¶Сѓ вЂ” С‡РµСЂРµР· РїСЂРѕРєСЃРё, `0.0.0.0` вЂ” РїСѓР±Р»РёС‡РЅРѕ) |
| `API_PREFIX` | `/api/v1` | РџСЂРµС„РёРєСЃ API |
| `REGISTER_TOKEN` | (РїСѓСЃС‚Рѕ) | РўРѕРєРµРЅ Р·Р°РїРёСЃРё; РїСЂРё Р·Р°РґР°РЅРёРё `register/delete/alerts` Рё `GET /devices` С‚СЂРµР±СѓСЋС‚ `Authorization: Bearer <token>` |
| `REGISTRY_FILE` | `data/devices.json` | Р¤Р°Р№Р» СЂРµРµСЃС‚СЂР° СѓСЃС‚СЂРѕР№СЃС‚РІ |
| `ALERTS_FILE` | `data/alerts.json` | Р¤Р°Р№Р» Р°Р»РµСЂС‚РѕРІ |
| `RULES_FILE` | `data/rules.json` | Р¤Р°Р№Р» РїСЂР°РІРёР» |
| `METRICS_FILE` | `data/metrics.json` | РСЃС‚РѕСЂРёСЏ РјРµС‚СЂРёРє СЃРµСЂРІРµСЂР° |
| `STABILITY_FILE` | `data/stability.json` | Р–СѓСЂРЅР°Р» СЃС‚Р°С‚СѓСЃРѕРІ СѓСЃС‚СЂРѕР№СЃС‚РІ |
| `SETTINGS_FILE` | `data/settings.json` | РќР°СЃС‚СЂРѕР№РєРё РїР°РЅРµР»Рё (РїРµСЂРµРѕРїСЂРµРґРµР»СЏСЋС‚ env) |
| `METRICS_INTERVAL_MS` | `10000` | РџРµСЂРёРѕРґ СЃСЌРјРїР»Р° РјРµС‚СЂРёРє |
| `METRICS_FLUSH_SECONDS` | `120` | РџРµСЂРёРѕРґ РїРµСЂСЃРёСЃС‚Р° РјРµС‚СЂРёРє |
| `METRICS_HOURS` | `24` | Р“Р»СѓР±РёРЅР° РёСЃС‚РѕСЂРёРё РјРµС‚СЂРёРє (Р°РіСЂРµРіР°С†РёСЏ РїРѕ РјРµСЂРµ СЂРѕСЃС‚Р°) |
| `PANEL_PASSWORD` | (РїСѓСЃС‚Рѕ) | РџР°СЂРѕР»СЊ РІРµР±-РїР°РЅРµР»Рё; **РїСѓСЃС‚Рѕ = РїР°РЅРµР»СЊ РѕС‚РєР»СЋС‡РµРЅР° (503)** |
| `PANEL_SESSION_TTL_MS` | `86400000` | TTL СЃРµСЃСЃРёРё РїР°РЅРµР»Рё |
| `STALE_MS` | `180000` | Р‘РµР· heartbeat Р·Р° СЌС‚Рѕ РІСЂРµРјСЏ СѓСЃС‚СЂРѕР№СЃС‚РІРѕ СЃС‡РёС‚Р°РµС‚СЃСЏ offline |
| `MAX_DEVICES_PER_IP` | `3` | РњР°РєСЃРёРјСѓРј СѓСЃС‚СЂРѕР№СЃС‚РІ СЃ РѕРґРЅРѕРіРѕ IP |
| `RATE_LIMIT_WINDOW_MS` | `60000` | РћРєРЅРѕ rate-limit |
| `RATE_LIMIT_*` | вЂ” | Р›РёРјРёС‚С‹ register/heartbeat/write/read |

## Р’РµР±-РїР°РЅРµР»СЊ

РћС‚РєСЂС‹РІР°РµС‚СЃСЏ РЅР° `GET {API host}/panel` (РєСЂР°С‚РєР°СЏ С„РѕСЂРјР° вЂ” `/panel`). РўСЂРµР±СѓРµС‚
`PANEL_PASSWORD` (РІ РїСЂРѕС‚РёРІРЅРѕРј СЃР»СѓС‡Р°Рµ РѕС‚РґР°С‘С‚ 503). Р’С…РѕРґ вЂ” РµРґРёРЅС‹Р№ РїР°СЂРѕР»СЊ, СЃРµСЃСЃРёСЏ вЂ”
HMAC-cookie `iot_panel` (HttpOnly, SameSite=Lax, Secure РїСЂРё HTTPS).

- `POST /panel/api/auth/login` `{ password }` В· `POST /panel/api/auth/logout`
- `GET  /panel/api/session` вЂ” СЃС‚Р°С‚СѓСЃ СЃРµСЃСЃРёРё, РІРµСЂСЃРёСЏ, РїСѓС‚СЊ РїР°РЅРµР»Рё
- `GET  /panel/api/system` вЂ” СЃРІРѕРґРєР° (devices/alerts/rules/cpu/mem/uptime)
- `GET  /panel/api/system/history?points=120` вЂ” РјРµС‚СЂРёРєРё РґР»СЏ РіСЂР°С„РёРєРѕРІ
- `GET/POST/PUT/DELETE /panel/api/devices[/:id]` вЂ” CRUD СѓСЃС‚СЂРѕР№СЃС‚РІ (detail РѕС‚РґР°С‘С‚
  stability + СЃРІСЏР·Р°РЅРЅС‹Рµ Р°Р»РµСЂС‚С‹/РїСЂР°РІРёР»Р°)
- `GET  /panel/api/settings`, `PUT /panel/api/settings` вЂ” РЅР°СЃС‚СЂРѕР№РєРё СЂР°РЅС‚Р°Р№РјР°
  (`stale_ms`, `metrics_hours`, `max_devices_per_ip`, `session_ttl_ms`,
  `rate_limits`, `api_token`, `panel_password`)
- `POST /panel/api/restart` вЂ” flush Рё РїРµСЂРµР·Р°РїСѓСЃРє РїСЂРѕС†РµСЃСЃР°

Р’СЃРµ panel-СЌРЅРґРїРѕРёРЅС‚С‹ С‚СЂРµР±СѓСЋС‚ Р¶РёРІСѓСЋ СЃРµСЃСЃРёСЋ (РёР»Рё Bearer-С‚РѕРєРµРЅ РїСЂРё РµРіРѕ Р·Р°РґР°РЅРёРё).
API-РєРѕРЅС‚СЂР°РєС‚ РґР»СЏ РїСЂРёР»РѕР¶РµРЅРёСЏ (`/api/v1/*`) РЅРµ РјРµРЅСЏРµС‚СЃСЏ.

## API

- `GET  /api/v1/health`
- `GET  /api/v1/devices` (+ С„РёР»СЊС‚СЂС‹ `status`/`online`, РїРѕРёСЃРє `q`)
- `POST /api/v1/devices/register` вЂ” СЂРµРіРёСЃС‚СЂР°С†РёСЏ СѓСЃС‚СЂРѕР№СЃС‚РІР° (rate-limit)
- `POST /api/v1/devices/heartbeat` вЂ” РѕР±РЅРѕРІР»РµРЅРёРµ СЃС‚Р°С‚СѓСЃР° (rate-limit)
- `DELETE /api/v1/devices/:id`
- `GET/POST /api/v1/alerts`, `PUT/DELETE /api/v1/alerts/:id`
- `GET/POST /api/v1/rules`, `PUT/DELETE /api/v1/rules/:id`

Р¤РѕСЂРјР°С‚ РїСЂР°РІРёР» (`models/smart_rule.dart` РІ РїСЂРёР»РѕР¶РµРЅРёРё): `trigger = threshold_above |
threshold_below | online | offline | no_data`, `action = notify | mqtt_command |
device_command`.

## Docker

```bash
# РєРѕРЅС„РёРіСѓСЂР°С†РёСЏ
REGISTER_TOKEN=... docker compose up -d --build
# РёР»Рё РЅР°РїСЂСЏРјСѓСЋ
docker build -t aeris-signaling-server .
docker run -d -p 3100:3100 \
  -e REGISTER_TOKEN=... -v "$PWD/data:/app/data" aeris-signaling-server
```

РџРѕР»РЅС‹Р№ self-hosted СЃС‚РµРє (node + mosquitto + nginx + certbot) РѕРїРёСЃР°РЅ РІ
РјРѕРЅРѕСЂРёР»РѕР¶РµРЅРёРё РІ `deploy/docker/README.md` вЂ” С‚Р°Рј СЌС‚РѕС‚ СЃРµСЂРІРµСЂ РёСЃРїРѕР»СЊР·СѓРµС‚СЃСЏ РєР°Рє
РєРѕРЅС‚РµР№РЅРµСЂ `server` РІРЅСѓС‚СЂРё СЃРµС‚Рё `iot`.

## Р›РёС†РµРЅР·РёСЏ

MIT