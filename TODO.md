# Aeris Monitor — TODO

> Обновлено **11.11.2026** после ревизии и серии исправлений.
>
> **Приоритеты:** `P0` — блокер/безопасность, `P1` — важно, `P2` — улучшение.
> Отмечайте `[x]` по мере выполнения. Команды проверки — в конце файла.

## Принятые решения (11.11.2026)

- **P0 №5:** секреты убрать из образа → NVS/провижининг.
- **P1 №4:** реализовать управление актуаторами/реле.
- **P1 №5:** перевести MQTT на TLS (8883).
- **Git:** разбить изменения на логические коммиты.
- **Reboot VPS:** выполнить сейчас.
- **Старый VPS:** архивы не трогать.

---

## P0 — критично

- [x] **Фикс MQTT-топика задеплоен.** *(11.11.2026)*
  Прошивка и приложение слушают `iot/<id>/commands`; сервер публиковал в `iot/<id>/cmd`.
  - Исправлены `server/src/app.js`, `server/src/rules_engine.js`, тесты.
  - Контейнер `iot-selfhost-server-1` пересобран; в нём `/commands`; health 200.

- [ ] **Перепрошить офлайн-устройство по USB (однократно).** *(заблокировано: подключён только COM1)*
  В опубликованном `/fw/main.bin` зашит `MQTT_BROKER "2.26.98.234"` (старый VPS) и `IoT-Setup`,
  поэтому по OTA устройство не выйдет на новый брокер.
  - Подключить ESP32-C3 по USB и выполнить:
    `powershell -File deploy/flash_device.ps1 -Environment esp32-c3`
    (или `-Port COM5`).
  - Критерий: в serial-логе `MQTT: Connected to spe4naz.online:1883`, устройство онлайн в панели.
  - После этого все дальнейшие обновления — только OTA.

- [x] **Скомпрометированные секреты ротированы.** *(11.11.2026)*
  - [x] Новый пароль MQTT устройства `main`: обновлены `runtime/mqtt/secrets/passwd`,
        `MQTT_DEVICE_PASSWORD` в `.env`, `MQTT_PASSWORD` в `secrets.h`.
        Проверено: новый — OK, старый — отказ.
  - [x] Новый `REGISTER_TOKEN`: обновлены `.env`, `secrets.h`; контейнер пересоздан.
        Проверено: новый — 200, старый — 401.
  - [ ] **Обновить токен в приложении:** Настройки → «Токен доступа (API)».
        Значение — `SIGNALING_TOKEN` в `firmware/main_controller/include/secrets.h`.
        MQTT-пароль приложения (`app`) не менялся.
  - [ ] Перепрошить устройство (см. пункт выше) — новый пароль уже в собранной прошивке.

- [x] **`MQTT_DEVICE_PASSWORD` задан в `.env`.** *(11.11.2026)*
  Совпадает с `secrets.h` (len=32). При пересоздании тома `main` больше не станет `changeme`.

- [ ] **P0 №5 — NVS/провижининг (реализовано, сборка успешна).** *(решение 11.11.2026)*
  Убрать рабочие секреты из образа: MQTT-пароль и `REGISTER_TOKEN` вводить при первичной
  настройке и хранить в NVS. `/fw` остаётся публичным, но бинарь без секретов.
  - [x] Модуль `DeviceSecrets` (`Preferences`), fallback на compile-time значения.
  - [x] `mqttConnect` и `signaling_client` читают NVS.
  - [x] Страница провижининга: поля MQTT user/password и signaling token.
  - [x] Миграция compile-time значений в NVS при первом старте.
  - [x] `-DAERIS_NO_COMPILED_SECRETS` + `deploy/build_fw_release.ps1` с проверкой утечки.
  - [x] Сборка C3/S3 1.2.3 с NVS/TLS — успешно; USB-версии в `deploy/installer/output/fw-usb/`.
  - [x] Релизная сборка без секретов проверена: `deploy/installer/output/fw-release/`.
  - [ ] Прошить и проверить регистрацию/MQTT на устройстве.
  - [ ] Опубликовать релизный бинарь 1.2.3 (после проверки на железе).

- [ ] **Публикация прошивки 1.2.3.**
  - [x] `FIRMWARE_VERSION` поднят до `1.2.3` в `config.h`.
  - [ ] Дождаться USB-проверки на устройстве.
  - [ ] Собрать релиз без секретов: `deploy/build_fw_release.ps1`.
  - [ ] Опубликовать: `deploy/build_fw_release.ps1 -Publish` (или `deploy/fw.ps1`).

---

## P1 — важно

- [x] **Запас OTA-слота ESP32-C3 увеличен.** *(11.11.2026)*
  - SPIFFS (`0xC0000`, 768 КБ) не использовался — удалён; `app0`/`app1` → `0x1E0000` (1.875 МБ).
  - Сборка C3/S3 успешна; `firmware.bin` = **73.8%** слота, запас **~503 КБ**.
  - Новая таблица применяется только при USB-прошивке.

- [x] **SSE `/api/v1/stream` закрыт авторизацией.** *(11.11.2026)*
  - `server/src/app.js` (`handleStream`), тест `server/test/sse.test.js` обновлён.
  - На VPS: без токена — `401`, с новым токеном — `200` + `: connected`.

- [ ] **Восстановить исходники веб-панели.**
  В `server/web` только собранный `dist`; `npm run build:panel` падает (нет `web/package.json`).
  - Критерий: панель собирается из исходников и деплоится.

- [ ] **P1 №4 — управление актуаторами (реализовано, сборка успешна).** *(решение 11.11.2026)*
  - [x] Модуль `RelayControl` (`relay_control.h/.cpp`), безопасное состояние «выключено» при старте.
  - [x] `RELAY_PIN` / `RELAY_ACTIVE_HIGH` в `config.h` (по умолчанию `-1` — выход отключён).
  - [x] Команды: `{"command":"relay","state":"on|off|toggle"}`, `{"relay":true|false}`,
        `relay:on|off|toggle` — в MQTT, WebSocket и HTTP.
  - [x] Публикация состояния: `iot/<id>/relay` и поле `relay` в статусе.
  - [x] GPIO реле: **GPIO 3**, активный **HIGH** (C3); на S3 выход отключён (`-DRELAY_PIN=-1`).
  - [ ] Пересобрать и проверить на железе: включение/выключение, состояние после перезагрузки.

- [x] **P1 №5 — MQTT TLS (8883).** *(11.11.2026)*
  - [x] Mosquitto: listener `8883` + сертификаты (обновлены до 09.02.2027); `1883` — только
        `127.0.0.1` для локального bridge/диагностики.
  - [x] Прошивка: `WiFiClientSecure` + ISRG Root X1, порт `8883`.
  - [x] Приложение: native — `8883` TLS, web — `9002` wss; миграция старых портов.
  - [x] Проверено: публичный `8883` открыт, `1883` снаружи закрыт, `TLS_AUTH_OK`, сертификат
        `CN=spe4naz.online` до 09.02.2027.
  - [ ] Проверить на реальном устройстве/телефоне.

---

## P2 — улучшения и гигиена

- [ ] **Портативность `platformio.ini`.** *(попытка не удалась)*
  Жёсткий путь `-IC:/Users/Spe4naz/.platformio/packages/framework-arduinoespressif32/libraries/Network/src`.
  `${platformio.packages_dir}` раскрывается в битый `builder/UsersSpe4naz.platformiopackages/...`.
  - Искать вариант через `$PROJECT_PACKAGES_DIR`, `extra_scripts` или явную зависимость `Network`.
  - Критерий: C3 и S3 собираются на другой машине/CI.

- [x] **Git — разбито на логические коммиты.** *(11.11.2026)*
  - [x] `docs:` ребрендинг + сайт/вики.
  - [x] `feat(app):` Android, фоновые уведомления, MQTT TLS.
  - [x] `fix(server):` `/commands`, SSE-авторизация.
  - [x] `feat(firmware):` NVS, TLS, реле, 1.2.3.
  - [x] `chore(deploy):` host nginx, TLS, инструменты, TODO.
  - Новые файлы сервера: `server/src/{config,ingest,metrics,mqtt_client,rules,rules_engine,session,settings,stability,static}.js`.
  - Новые тесты: `server/test/{ingest,metrics,mqtt_client,panel,panel_disabled,registry_update,rules,rules_engine,session,settings,sse,stability}.test.js`.
  - Вся вики: `deploy/site/wiki/` — **13 untracked файлов**.
  - `firmware/main_controller/include/secrets.h.example` (только заглушки).
  - Ребрендинг, Android, compose, docs, `TODO.md`, `deploy/flash_device.ps1`.

- [ ] **Удалить/обновить устаревшее.**
  - `deploy/installer/output/iot-modular-app_1.1.0_amd64.deb` (старый бренд/версия).
  - `deploy/iot.conf` — legacy bare-metal mosquitto.
  - `deploy/site/wiki/server.html` — systemd/`/opt/iot-server`/`/var/www/iot-site` вместо Docker.
  - `firmware/test_simple/platformio.ini` — `espressif32@6.5.0`, который, по комментариям, нестабилен.

- [ ] **Обновить `share_plus`.**
  Текущая версия применяет Kotlin Gradle Plugin; будущие Flutter могут не собрать APK.
  - Критерий: `flutter build apk --release` без KGP-warning.

- [ ] **Переименовать пакет сервера.**
  `server/package.json` → `"name": "iot-signaling-server"` (косметика).

- [ ] **Проверить APK на реальном телефоне.**
  - [ ] Установка из неизвестного источника.
  - [ ] Фоновые уведомления при закрытом приложении (правило → системное уведомление).
  - [ ] Обновить токен в настройках → проверить, что SSE/уведомления ожили.
  - [ ] OTA-кнопки (`ota`/`rollback`/`restart`).
  - [ ] CSV через «Поделиться».
  - [ ] Провизжининг Wi-Fi через `Aeris-Setup-XXXX` → `http://192.168.4.1`.

- [x] **Тест перезагрузки VPS.** *(11.11.2026: успешно)*
  После `reboot`: хост вернулся, `nginx`/`certbot.timer` активны, все разделы 200,
  контейнеры healthy, SSE (401/200) и MQTT (`APP_AUTH_OK`) работают, сертификат до 09.02.2027.

- [x] **Старый VPS `2.26.98.234` — решение: не трогать.** *(архивы ~4.7 ГБ оставлены)*

- [ ] **Документация.**
  - [x] Инструкция по ротации секретов — `deploy/docker/README.md`.
  - [ ] `PROJECT_OVERVIEW.md`/`README.md` под текущую схему (host nginx + Docker на loopback).
  - [ ] Раздел про публикацию прошивки и NVS-провижининг.

---

## ✅ Сделано

### Ревизия и исправления
- [x] Собраны прошивки ESP32-C3, ESP32-S3, ESP32-C6 — 0 ошибок.
- [x] Сервер: 155/155 тестов; приложение: analyze 0 ошибок/предупреждений, 80/80 тестов.
- [x] Критичный топик команд: `iot/<id>/cmd` → `iot/<id>/commands` + тесты.
- [x] Ребрендинг UI: `MaterialApp.title`, `AppConfig.appName`, «О программе», версия 1.2.0.
- [x] SSID `IoT-Setup-XXXX` → `Aeris-Setup-XXXX` (прошивка, приложение, сайт, вики).
- [x] `analysis_options.yaml`: исключён `third_party/**`.
- [x] `deploy/iot-site.conf` приведён к схеме host nginx → `127.0.0.1:8080`.
- [x] `.env.example`, `docker-compose.yml`, `acl.template` — бренд; `MQTT_DEVICE_USER=main`.
- [x] Проверены секреты: 0 утечек в 498 файлах; `secrets.h`/`.jks`/`.env` игнорируются.
- [x] OTA: CA ISRG Root X1 + SHA-256.
- [x] C3: SPIFFS удалён, OTA-слоты 1.875 МБ, запас ~503 КБ.
- [x] SSE-авторизация; Mosquitto `passwd` — `mosquitto:mosquitto` 600.
- [x] Ротированы MQTT-пароль устройства и `REGISTER_TOKEN`; значения синхронизированы.
- [x] При смене токена/URL фоновый SSE-монитор перезапускается.
- [x] Добавлены `deploy/flash_device.ps1` и инструкция ротации.
- [x] Удалён мусорный файл `4`.
- [x] Пересобраны и задеплоены: прошивки C3/S3, web, APK, сайт, вики.
- [x] Бэкапы: ежедневно 03:00, 16 копий, последняя — сегодня.
- [x] `certbot renew --dry-run` — успешно для обоих доменов.
- [x] Оба сайта публично: `spe4naz.online` и `shorkey.online` — 200.

### Артефакты
- APK: `deploy/installer/output/aeris-monitor-1.2.0.apk`
  SHA256 `2b3cbb62619e09b514a25a898747c464356ea0143380702f406724640823e07b`.
- Прошивки: `firmware/main_controller/.pio/build/{esp32-c3,esp32-s3}/firmware.bin`.
- USB-прошивки (с секретами): `deploy/installer/output/fw-usb/`.
- Релизные прошивки (без секретов, проверено): `deploy/installer/output/fw-release/`.
- TLS: `8883` (MQTT), `9002` (wss), `1883` только loopback.
- NVS-провижининг: `DeviceSecrets`, поля на `Aeris-Setup`, миграция compile-time → NVS.
- Реле: `RelayControl` + команды в MQTT/WS/HTTP + публикация состояния.
- Git: 5 логических коммитов (`docs`, `app`, `server`, `firmware`, `deploy`).
- Публичный OTA (`/fw`) намеренно **не обновлялся** (старые секреты уже недействительны).

---

## Команды проверки

```powershell
# Прошивки
cd C:\IoTs\firmware\main_controller
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-c3
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-s3
cd ..\sensor_module
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-c6

# Сервер
cd C:\IoTs\server
npm test

# Приложение
cd C:\IoTs\mobile_app
C:\flutter\flutter\bin\flutter.bat analyze --no-fatal-infos
C:\flutter\flutter\bin\flutter.bat test

# Web + APK
C:\flutter\flutter\bin\flutter.bat build web --release
powershell -NoProfile -ExecutionPolicy Bypass -File C:\IoTs\deploy\app_android.ps1

# Сайты (с VPS)
curl -s -o /dev/null -w '%{http_code}\n' https://spe4naz.online/
curl -s -o /dev/null -w '%{http_code}\n' https://spe4naz.online/api/v1/health
curl -s -o /dev/null -w '%{http_code}\n' https://shorkey.online/
```
