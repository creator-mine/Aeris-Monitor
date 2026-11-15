# Aeris Monitor — TODO

> Обновлено **15.11.2026**. Только открытые задачи.
>
> **Приоритеты:** `P0` — блокер/безопасность, `P1` — важно, `P2` — улучшение.

## Текущее состояние

- **C6 `esp32c6_001`** — прошит по USB (factory 16 МБ), Wi-Fi `GGM-2G`
  (192.168.0.117), MQTT и API работают. Сейчас отключён от USB (офлайн).
  Датчиков и SD-карты нет.
- **S3 `esp32s3_001`** — прошит по USB 15.11.2026: **1.2.4** + USB CDC,
  MAC `14:c1:9f:36:7e:9c`, COM6. `verify-flash` — digest совпал.
  MQTT/API-доступы записаны в NVS из приложения. Wi-Fi ещё не задан:
  висит в AP `Aeris-Setup-F6EC` (нужен пароль `GGM-2G`).
- **C3** — не прошит после смены брокера, в `/fw` лежит 1.2.2 (см. P0).
- **Публикации `/fw`:** C3 — 1.2.2, C6 — 1.2.3; 1.2.4 не опубликована.
- **Артефакты:** прошивка 1.2.4 (C3/C6/S3) без секретов; APK 1.2.1;
  установщик Windows 1.2.1 (`a8c34245…`).

---

## P0 — критично

- [ ] **Перепрошить ESP32-C3 по USB (однократно).**
  В опубликованном `/fw/main.bin` зашит старый брокер `2.26.98.234`, поэтому по
  OTA устройство не выйдет на новый.
  - `powershell -File deploy/flash_device.ps1 -Environment esp32-c3 -Port COMx`
  - Критерий: в логе `MQTT: Connected to spe4naz.online:8883`, устройство онлайн.
  - Скрипт сохраняет NVS; `-EraseAll` — только для чистой платы.

- [ ] **Довести S3 до онлайна (проверка 1.2.4 в сети).**
  Плата прошита по USB и настроена по USB, но Wi-Fi не задан
  (висит в AP `Aeris-Setup-F6EC`).
  - Задать `GGM-2G` в приложении → «Настройка» → «Подключение к Wi-Fi».
  - Критерий: `CMD:info` отдаёт `wifi_connected:true` и IP, в логе
    `MQTT: Connected to spe4naz.online:8883`, устройство онлайн в панели
    с версией 1.2.4.

- [ ] **Опубликовать прошивку 1.2.4 в `/fw`.**
  - Только после проверки на C3, C6 и S3 (S3 — ещё не выходил в сеть).
  - `powershell -File deploy/build_fw_release.ps1 -Publish`
  - Проверить, что `/fw` отдаёт 1.2.4 для C3, C6 и S3.

---

## P1 — важно

- [ ] **Проверить датчики и SD-карту на C6.**
  - Датчики подключаются к UART1 (RX = GPIO4, TX = GPIO5); сейчас
    `Active modules: 0`.
  - SD: `Mount failed`, CS = GPIO10. Без карты нет истории и графиков.
  - Критерий: модули видны в панели, графики строятся за выбранный период.

- [ ] **Проверить реле на железе.**
  GPIO 3, активный HIGH (C3); на S3 выход отключён.
  - Команды: `relay:on` / `relay:off` / `relay:toggle`,
    `{"command":"relay","state":"on"}`, `{"relay":true}`.
  - Проверить включение/выключение и состояние после перезагрузки (должно быть off).
  - Состояние публикуется в `iot/<id>/relay` и в поле `relay` статуса.

- [ ] **Восстановить исходники веб-панели.**
  В `server/web` только собранный `dist`; `npm run build:panel` падает
  (нет `web/package.json`).
  - Критерий: панель собирается из исходников и деплоится.

- [ ] **Проверить APK на телефоне (TLS, уведомления, OTA, CSV).**
  APK: `deploy/installer/output/aeris-monitor-1.2.1.apk`
  SHA256 `d82730748d9aea7691f3d161e870e6d8f05185778bd867b9b21128f70d0d5deb`,
  versionCode 4, ключ `aeris-release.jks`.
  - Установка из неизвестного источника.
  - MQTT `8883` TLS и фоновые уведомления при закрытом приложении.
  - OTA-кнопки (`ota`/`rollback`/`restart`), CSV через «Поделиться».
  - Провижининг через `Aeris-Setup-XXXX` → `http://192.168.4.1`.

---

## P2 — улучшения

- [ ] **Проверить установщик Windows.**
  `deploy/installer/output/aeris_setup_1.2.1.exe`
  SHA256 `a8c342456cca659074788d2168ec223be7f3d211217648d3aa27fbe07205010f`.
  - Установка, запуск, COM-порты и системные уведомления.
  - MQTT, OTA и экспорт CSV.
  - Установщик не подписан — Windows SmartScreen покажет предупреждение.

---

## Команды проверки

```powershell
# Прошивки (без секретов)
$env:PLATFORMIO_BUILD_FLAGS='-DAERIS_NO_COMPILED_SECRETS'
cd C:\IoTs\firmware\main_controller
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-c3
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-c6
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-s3
cd ..\sensor_module
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-c6

# USB-прошивка платы (NVS сохраняется: пишутся только bootloader/таблица/app)
powershell -File C:\IoTs\deploy\flash_device.ps1 -Environment esp32-s3 -Port COM6
powershell -File C:\IoTs\deploy\flash_device.ps1 -Environment esp32-c6 -Port COM7
powershell -File C:\IoTs\deploy\flash_device.ps1 -Environment esp32-c3 -Port COMx -EraseAll

# Проверка, что в плате именно собранный образ
$py = 'C:\Users\Spe4naz\.platformio\penv\Scripts\python.exe'
$esp = 'C:\Users\Spe4naz\.platformio\packages\tool-esptoolpy\esptool.py'
& $py $esp --port COM6 --chip esp32s3 verify-flash 0x10000 `
  C:\IoTs\firmware\main_controller\.pio\build\esp32-s3\firmware.bin

# Сервер
cd C:\IoTs\server
npm test

# Приложение
cd C:\IoTs\mobile_app
C:\flutter\flutter\bin\flutter.bat analyze --no-fatal-infos
C:\flutter\flutter\bin\flutter.bat test

# Web + APK + Windows
C:\flutter\flutter\bin\flutter.bat build web --release
powershell -NoProfile -ExecutionPolicy Bypass -File C:\IoTs\deploy\app_android.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\IoTs\deploy\app_windows.ps1

# Сайты (с VPS)
curl -s -o /dev/null -w '%{http_code}\n' https://spe4naz.online/
curl -s -o /dev/null -w '%{http_code}\n' https://spe4naz.online/api/v1/health
curl -s -o /dev/null -w '%{http_code}\n' https://shorkey.online/
```
