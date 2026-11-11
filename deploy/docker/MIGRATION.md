# Перенос IoT-сервера на другую VPS (bare-metal → Docker)

Эта инструкция переносит **только IoT-часть** (домен `spe4naz.online`): сигнальный
сервер, реестр, правила/алерты, MQTT-брокер с учётками устройств, веб-панель,
лендинг + вики + OTA-прошивки и Flutter-web приложение. Другие сайты на старом
VPS (vibeverse, lumira-server.ru и т.п.) не затрагиваются.

Переносится **как есть**: те же учётки MQTT (устройства не нужно перепрошивать),
тот же `REGISTER_TOKEN`, пароль панели и сертификаты Let's Encrypt.

## Что где живёт

| Данные | Старый VPS (bare-metal) | Новый стек (Docker) |
|---|---|---|
| Реестр/метрики/ingest | `/opt/iot-server/data` | `deploy/docker/runtime/data` |
| MQTT учётки (passwd/acl) | `/etc/mosquitto/{passwd,acl}` | `deploy/docker/runtime/mqtt/secrets` |
| MQTT TLS-сертификаты (9002) | `/etc/mosquitto/certs` | `deploy/docker/runtime/mqtt/certs` |
| Let's Encrypt | `/etc/letsencrypt` | `deploy/docker/runtime/letsencrypt` |
| Лендинг + вики + `/fw` | `/var/www/iot-site` | `deploy/docker/runtime/site` |
| Flutter-web (`/app/`) | `/var/www/app` | `deploy/docker/runtime/site/app` |
| Env (PANEL_PASSWORD, bridge) | `/etc/iot-server/env` | `deploy/docker/.env` |

Весь изменяемый стейт нового стека — в `deploy/docker/runtime/` (bind-mount'ы), поэтому
бэкап и повторный перенос = упаковать `runtime/` + `.env`.

## Требования к новой VPS

- Ubuntu 24.04 (или совместимый), root/sudo, ≥ 1 ГБ RAM (рекомендуется 2 ГБ).
- Свободны порты: `80`, `443`, `1883`, `9001`, `9002`.
- DNS: A-запись `spe4naz.online` → **IP новой VPS** (переключить на шаге 4).

## Шаг 1. Экспорт со старого VPS

```bash
# на СТАРОМ VPS (2.26.98.234), от root
git/scp не нужен — берём только данные
sudo bash export.sh spe4naz.online /root
# -> /root/iot-migration-spe4naz.online-<stamp>.tar.gz (+ .sha256)
```

`export.sh` только читает. Что попадает в архив: данные сервера, `passwd`/`acl`,
MQTT-сертификаты, `/etc/letsencrypt`, контент сайта и приложения, env-файл,
`REGISTER_TOKEN` из systemd-юнита, плюс reference-конфиги nginx/mosquitto.

> Внимание: архив содержит секреты (пароли, приватные ключи). Передавайте по
> защищённому каналу и удаляйте после переноса.

## Шаг 2. Доставить на новую VPS

Нужны две вещи: **репозиторий** (папки `server/` и `deploy/`) и **бандл** из шага 1.

```bash
# с локальной машины (Windows PowerShell)
scp -i <key> -r C:\IoTs\server C:\IoTs\deploy root@NEW_VPS:/opt/iot/
scp -i <key> C:\IoTs\vps-backup\iot-migration-*.tar.gz root@NEW_VPS:/root/
```

Репозиторий можно разместить в любом каталоге; `import.sh` найдёт `deploy/docker`
относительно своего расположения (или укажите `--repo /opt/iot`).

## Шаг 3. Импорт и запуск

```bash
# на НОВОМ VPS, от root
cd /opt/iot/deploy/docker/migrate
sudo bash import.sh /root/iot-migration-spe4naz.online-<stamp>.tar.gz --repo /opt/iot
```

Скрипт: установит Docker (если нет) → распакует бандл в `../runtime/` → соберёт `.env`
из импортированных секретов → настроит `ufw` → `docker compose --profile certbot up -d --build`.

Проверка (до переключения DNS, по IP):

```bash
curl -s http://127.0.0.1/api/v1/health          # {"status":"ok",...}
docker compose -f /opt/iot/deploy/docker/docker-compose.yml ps
docker compose -f /opt/iot/deploy/docker/docker-compose.yml logs -f server mqtt web certbot
```

`--no-up` — только подготовить стейт/`.env` без запуска.

## Шаг 4. Переключение DNS и проверка

1. Смените A-запись `spe4naz.online` на IP новой VPS и дождитесь TTL.
2. Проверьте HTTPS и все разделы:
   - `https://spe4naz.online/api/v1/health`
   - `https://spe4naz.online/panel/` (пароль из импортированного env)
   - `https://spe4naz.online/app/` (Flutter-web)
   - `https://spe4naz.online/fw/version.json`
   - MQTT: приложение подключается к `spe4naz.online:9001` (или `:9002` wss) с прежними логином/паролем.
3. Убедитесь, что устройство снова онлайн (heartbeat) и команды идут.
4. Продлите сертификат при необходимости: `docker compose run --rm certbot certbot renew`.

## Продление сертификатов

Контейнер `certbot` продлевает сертификат автоматически (каждые 12 ч), а nginx
подхватывает новый через watcher. Сертификат для MQTT (wss `9002`) хранится
копией в `runtime/mqtt/certs` — обновить его после продления:

```bash
cd /opt/iot/deploy/docker/migrate
sudo bash refresh-certs.sh
```

(Скрипт принудительно продлевает, копирует свежие certs в mosquitto и
перезапускает `mqtt` + перезагружает `web`.)

## Шаг 5. Вывод старого VPS из эксплуатации

```bash
# на СТАРОМ VPS
systemctl disable --now iot-server
systemctl disable --now mosquitto
# удалить сайт /etc/nginx/sites-enabled/iot-site и reload nginx (если это единственный IoT-сайт)
# опционально: crontab -r, если других задач нет
```

Не удаляйте `/opt/iot-server` и `/etc/mosquitto` до подтверждённой стабильной работы нового сервера.

## Откат

Пока старый VPS не выведен, откат = вернуть A-запись на старый IP и
`systemctl start iot-server mosquitto`. Данные на новом сервере — копия, старый не изменялся.

## Замечания по безопасности

- `deploy/docker/.env` создаётся с правами `0600` и содержит секреты — не коммитьте (уже в `.gitignore`).
- `runtime/letsencrypt` и `runtime/mqtt/certs` содержат приватные ключи — ограничьте доступ.
- Порт `3100` наружу не публикуется (доступ только через nginx внутри сети `iot`).
- На новом VPS смените пароль панели и `REGISTER_TOKEN` после успешного переезда (в `.env` + панели).
