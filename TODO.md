# Aeris Monitor — TODO

> Обновлено **11.11.2026**. Только открытые задачи.
>
> **Приоритеты:** `P0` — блокер/безопасность, `P1` — важно, `P2` — улучшение.

---

## P0 — критично

- [ ] **Перепрошить ESP32-C3 по USB (однократно).**
  В опубликованном `/fw/main.bin` зашит старый брокер `2.26.98.234`, поэтому по OTA
  устройство не выйдет на новый. Прошивка 1.2.3 уже собрана.
  - Подключить по USB и выполнить:
    `powershell -File deploy/flash_device.ps1 -Environment esp32-c3`
    (или `-Port COM5`).
  - Критерий: в serial-логе `MQTT: Connected to spe4naz.online:8883`, устройство онлайн в панели.
  - Сейчас устройство не подключено (виден только COM1).
  - Бинарники: `deploy/installer/output/fw-usb/`.

- [ ] **Обновить токен в приложении.**
  - Новый `SIGNALING_TOKEN` — в `firmware/main_controller/include/secrets.h`.
  - Приложение → Настройки → **«Токен доступа (API)»** → «Применить».
  - MQTT-пароль приложения (`app`) не менялся.

- [ ] **Проверить NVS-провижининг на устройстве.**
  - После USB-прошивки: `MQTT: Connected to spe4naz.online:8883`.
  - `Aeris-Setup-XXXX` → `http://192.168.4.1`: поля MQTT/API сохраняются в NVS.
  - Убедиться, что для работы не нужны секреты, вкомпилированные в образ.

- [ ] **Опубликовать прошивку 1.2.3 в `/fw`.**
  - Только после успешной проверки на устройстве.
  - `powershell -File deploy/build_fw_release.ps1 -Publish`
  - Релиз без секретов уже собран и проверен: `deploy/installer/output/fw-release/`.
  - Сейчас `/fw` намеренно остаётся на 1.2.2.

---

## P1 — важно

- [ ] **Восстановить исходники веб-панели.**
  В `server/web` только собранный `dist`; `npm run build:panel` падает
  (нет `web/package.json`).
  - Критерий: панель собирается из исходников и деплоится.

- [ ] **Проверить реле на железе.**
  GPIO 3, активный HIGH (C3); на S3 выход отключён.
  - Команды: `relay:on` / `relay:off` / `relay:toggle`,
    `{"command":"relay","state":"on"}`, `{"relay":true}`.
  - Проверить включение/выключение и состояние после перезагрузки (должно быть off).
  - Состояние публикуется в `iot/<id>/relay` и в поле `relay` статуса.

- [ ] **Проверить TLS на реальном телефоне/устройстве.**
  Native — `8883` TLS, web — `9002` wss; сертификат до 09.02.2027.
  - Установить APK, проверить MQTT и фоновые уведомления.

---

## P2 — улучшения и гигиена

- [ ] **Проверить APK на реальном телефоне.**
  APK: `deploy/installer/output/aeris-monitor-1.2.0.apk`
  SHA256 `bd1f4b46236c4bceea72aeaea1b8051376464fd09b4224d61324006bb298c957`.
  - [ ] Установка из неизвестного источника.
  - [ ] Фоновые уведомления при закрытом приложении (правило → системное уведомление).
  - [ ] Обновить токен в настройках → проверить, что SSE/уведомления ожили.
  - [ ] OTA-кнопки (`ota`/`rollback`/`restart`).
  - [ ] CSV через «Поделиться».
  - [ ] Провизжининг Wi-Fi через `Aeris-Setup-XXXX` → `http://192.168.4.1`.

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
