# Self-hosted развёртывание (Docker)

Полный стек Aeris Monitor в контейнерах: **node signaling-сервер + mosquitto (MQTT) + nginx (веб / OTA / прокси API / админ-панель) + certbot (автоматический TLS)**. Всё настраивается через один `.env`.

> Переносите существующий сервер на новую VPS? См. **[MIGRATION.md](MIGRATION.md)** — скрипты `migrate/export.sh` и `migrate/import.sh` переносят данные, MQTT-учётки, сертификаты и сайт без перепрошивки устройств.

Весь изменяемый стейт вынесен в `./runtime/` (bind-mount'ы): `runtime/data` (данные сервера),
`runtime/site` (лендинг + `/fw` + `/app`), `runtime/mqtt/{data,log,secrets,certs}`,
`runtime/letsencrypt`, `runtime/certbot-www`. Бэкап = упаковать `runtime/` и `.env`.

## Что входит

| Сервис | Описание |
|---|---|
| `server` | REST API/реестр устройств (`server/src`), данные в `runtime/data` (`devices.json`, `alerts.json`, `rules.json`, `metrics.json`, `stability.json`, `settings.json`, `ingest/`) |
| `mqtt` | Брокер mosquitto: `1883` (MQTT, устройства) + `9001` (WebSocket, приложение) + `9002` (wss, live-панель браузера). Пароли и ACL генерируются на первом старте из `.env` **или** импортируются из `runtime/mqtt/secrets` |
| `web` | nginx: `/api/` → сервер (SSE `/api/v1/stream`), `/fw/` → OTA-прошивки, `/panel/` → админ-панель, `/app/` → веб-версию приложения; содержимое из `runtime/site` |
| `certbot` | Выпуск и продление сертификата Let's Encrypt для `NGINX_DOMAIN` (профиль `certbot`) |

## Требования

- Сервер с Docker + compose-плагином (`docker compose version`), порты 80, 443, 1883, 9001 свободны.
- DNS A-запись: `NGINX_DOMAIN` → IP сервера (нужна для HTTPS; для HTTP-режима достаточно IP/имени в локальной сети).

## Шаг 1. Настройка

```bash
cd deploy/docker
cp .env.example .env
# отредактируйте:
#   NGINX_DOMAIN        — домен (или localhost/LAN-имя для HTTP-режима)
#   REGISTER_TOKEN      — токен записи API (защитит register/delete)
#   MQTT_USER / MQTT_PASSWORD           — учётка приложения
#   MQTT_DEVICE_USER / MQTT_DEVICE_PASSWORD — учётка устройств
```

## Шаг 2. Запуск

### HTTP-only (LAN, быстрый старт)

```bash
NGINX_TLS=0
docker compose up -d --build
```

### HTTPS с автоматическим сертификатом

```bash
NGINX_TLS=1
CERTBOT_EMAIL=you@example.com   # в .env
docker compose --profile certbot up -d --build
```

Проверка после запуска:

```bash
docker compose ps
docker compose logs -f server web certbot   # если certbot запущен
curl -s http://127.0.0.1/api/v1/health
```

## Шаг 3. Настройка приложения (mobile/web)

В разделе «Настройки → Подключение»:

| Поле | Значение |
|---|---|
| API URL | `https://<NGINX_DOMAIN>` (или `http://<ip>:80` в HTTP-режиме) |
| MQTT Брокер | `<NGINX_DOMAIN>` (или IP) |
| MQTT Порт | `9001` |
| MQTT Логин / Пароль | `MQTT_USER` / `MQTT_PASSWORD` |
| Токен записи (API) | `REGISTER_TOKEN` |
| OTA URL (прошивки) | оставьте пустым — берётся API URL (или укажите отдельный хост) |

Нажмите «Применить и переподключиться».

## Шаг 4. Прошивка устройств (ESP32)

В `firmware/<project>/include/config.h`:

- `SERVER_HOST` = `<NGINX_DOMAIN>` (регистрация и heartbeat через HTTP);
- MQTT: брокер `<NGINX_DOMAIN>`, порт `1883` (tcp), `mqtt_user`/`mqtt_password` из `.env` (`MQTT_DEVICE_USER`/`MQTT_DEVICE_PASSWORD`).

Устройство публикует `iot/<id>/sensors/#`, `iot/<id>/status` и слушает `iot/<id>/commands/#`. Прошивка логинит **все** устройства общим пользователем (`mqtt_user`/`mqtt_password` = `MQTT_DEVICE_USER`/`MQTT_DEVICE_PASSWORD`), а id устройства — в топике. Если нужно, чтобы устройства не могли публиковать чужие топики, заведите по пользователю на устройство и замените соответствующие строки в `deploy/docker/mqtt/acl.template` на `user <id>` с точными `iot/<id>/…`.

## Шаг 5. OTA-прошивки

Содержимое `runtime/site` монтируется в nginx как `/` (в т.ч. `/fw/`). При первом
запуске, если `runtime/site` пуст, он заполняется из `deploy/site`. Положите артефакты:

- `runtime/site/fw/main.bin` + `runtime/site/fw/version.json` (esp32-c3)
- `runtime/site/fw/main_esp32-s3.bin` + `runtime/site/fw/version-esp32-s3.json` (esp32-s3)
- `runtime/site/fw/main_esp32-c6.bin` + `runtime/site/fw/version-esp32-c6.json` (esp32-c6 controller)

Проще всего — существующий `deploy/fw.ps1`: он генерирует манифесты (sha256/version)
прямо в `deploy/site/fw`; скопируйте их в `runtime/site/fw/` на сервере (или публикуйте
напрямую по scp в `runtime/site/fw`).

## Бэкапы

Состояние лежит в bind-mount'ах `./runtime/`. Снимок — обычный tar:

```bash
cd deploy/docker
tar czf /var/backups/iot-$(date +%F).tar.gz runtime .env
```

Автоматический ежедневный бэкап: скрипт `backup.sh` (снапшот `runtime/` + `.env`,
ротация, хранение 14 копий в `/var/backups/iot/`, `iot-latest.tar.gz` — последний).
На Debian/Ubuntu добавьте в cron root'а (обычно уже настроено при деплое):

```cron
0 3 * * * /opt/iot/deploy/docker/backup.sh >> /var/log/iot-backup.log 2>&1
```

Восстановление: распаковать `runtime/` и `.env` на месте и `docker compose up -d`.
(Секреты и приватные ключи в `runtime/letsencrypt` и `runtime/mqtt/certs` — храните архив защищённо.)

## Совместный хостинг (несколько сайтов на одном VPS)

Если порты 80/443 уже заняты хостовым nginx (например, другим сайтом), не
публикуйте `web` наружу — пусть TLS и маршрутизацию делает хостовый nginx:

- в `docker-compose.yml`: `ports: ["127.0.0.1:8080:80"]`;
- в `.env`: `NGINX_TLS=0` (контейнер отдаёт HTTP, TLS завершает хост);
- vhost на хосте: `proxy_pass http://127.0.0.1:8080;` и `proxy_buffering off;`
  для SSE `/api/v1/stream`;
- сертификат выпускает/продлевает хостовый certbot:
  `certbot certonly --webroot -w /var/www/certbot -d <domain>`.

MQTT-порты (`1883/9001/9002`) при этом остаются опубликованными из контейнера.

## Замечания по безопасности

- Обязательно меняйте `REGISTER_TOKEN` и пароли MQTT (по умолчанию `changeme`).
- `api/v1/devices` (чтение реестра) без токена открыт — за NAT/брандмауэром нормально для LAN. Для публичного доступа задайте `REGISTER_TOKEN` и не открывайте лишние порты.
- Порт `3100` наружу не маппится (только внутри сети `iot` через nginx).
- МQTT-WS на `9001` — plain (без TLS), как и на продовом инстансе. Для критичных сетей поднимайте VPN/TLS.
- Let's Encrypt обновляется автоматически (продление каждые 12 ч, reload nginx раз в час). ВАЖНО: NGINX_TLS=1 требует, чтобы `NGINX_DOMAIN` резолвился снаружи на этот сервер (порт 80 доступен наружу).

## Состав каталога

```
deploy/docker/
├── docker-compose.yml
├── .env.example
├── README.md
├── MIGRATION.md               # перенос существующего сервера
├── server/Dockerfile          # node-сервер
├── mqtt/                      # mosquitto + генерация/импорт паролей и ACL
│   ├── Dockerfile
│   ├── mosquitto.conf
│   ├── acl.template
│   └── docker-entrypoint.sh
├── nginx/                     # веб/прокси/OTA/панель
│   ├── Dockerfile
│   ├── nginx-entrypoint.sh
│   └── conf/*.template
├── certbot/certbot-entrypoint.sh
├── migrate/                   # export.sh (старый VPS) + import.sh (новый VPS)
└── runtime/                   # состояние (gitignored): data, site, mqtt, letsencrypt…
```


## Ротация секретов

Публичный OTA-каталог `/fw` доступен без авторизации, поэтому **никогда не
публикуйте прошивку с рабочими секретами**. После любой утечки ротируйте их.

### Пароль MQTT устройства (пользователь `main`)

1. Обновить пароль в брокере:
   ```bash
   docker exec iot-selfhost-mqtt-1 \
     mosquitto_passwd -b /mosquitto/secrets/passwd main '<новый-пароль>'
   docker kill -s HUP iot-selfhost-mqtt-1
   ```
2. Записать тот же пароль в `MQTT_DEVICE_PASSWORD` (`.env`) и в
   `firmware/main_controller/include/secrets.h` (`MQTT_PASSWORD`).
3. Пересобрать прошивку и прошить устройство (USB один раз, далее OTA).

### `REGISTER_TOKEN` (API и signaling)

1. Заменить `REGISTER_TOKEN` в `.env`.
2. `docker compose up -d server` (контейнер пересоздастся с новым env).
3. Записать тот же токен в `SIGNALING_TOKEN` (`secrets.h`), пересобрать прошивку.
4. В приложении: **Настройки → «Токен доступа (API)»** — вставить новый токен.

### Пароль панели

1. Заменить `PANEL_PASSWORD` в `.env`.
2. `docker compose up -d server`.

Проверка после ротации: `mosquitto_pub` с новым паролем проходит, старый — нет;
`GET /api/v1/sensors/latest` с новым Bearer — `200`, без токена — `401`.


## MQTT TLS и хранение секретов

- **8883** — MQTT over TLS для устройств и нативных приложений.
- **9002** — secure WebSocket (wss) для браузерных клиентов.
- **1883** — только `127.0.0.1` (локальный bridge сервера и диагностика);
  снаружи порт закрыт.
- Сертификаты лежат в `runtime/mqtt/certs/` и обновляются из
  `/etc/letsencrypt/live/spe4naz.online/`; после замены — `docker compose restart mqtt`.

Прошивка **не содержит рабочих секретов**: MQTT-пользователь/пароль и API-токен
хранятся в NVS (`secrets`) и вводятся на странице `Aeris-Setup-XXXX`
(`http://192.168.4.1`). При первом старте compile-time значения из `secrets.h`
мигрируют в NVS.

- USB-прошивка (с секретами для удобства): `deploy/flash_device.ps1`.
- Публичная OTA-сборка (без секретов, с проверкой утечки):
  `deploy/build_fw_release.ps1` (и `-Publish` для выкладки в `/fw`).
