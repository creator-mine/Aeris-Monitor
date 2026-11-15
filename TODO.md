# Aeris Monitor — TODO

> Обновлено **15.11.2026**. Только открытые задачи.
>
> **Приоритеты:** `P0` — блокер/безопасность, `P1` — важно, `P2` — улучшение.

---

## P0 — критично

- [ ] **Перепрошить ESP32-C3 по USB (однократно).**
  В опубликованном `/fw/main.bin` зашит старый брокер `2.26.98.234`, поэтому по OTA
  устройство не выйдет на новый. Прошивка 1.2.4 уже собрана (в неё также входит
  исправление чтения истории с SD: новые файлы читаются первыми).
  - Подключить по USB и выполнить:
    `powershell -File deploy/flash_device.ps1 -Environment esp32-c3`
    (или `-Port COM5`).
  - Критерий: в serial-логе `MQTT: Connected to spe4naz.online:8883`, устройство онлайн в панели.
  - Сейчас устройство не подключено (виден только COM1).
  - Бинарники: `deploy/installer/output/fw-usb/`.

- [x] **Прошить ESP32-C6 по USB (16 МБ, factory-образ 1.2.4).**
  Выполнено 15.11.2026 через esptool 5.3.0: `write-flash 0x0` с `--erase-all`,
  1 533 600 байт, hash verified. MAC `e8:f6:0a:fb:f2:50`, порт COM7
  (USB-Serial/JTAG).
  - Найдено: у платы C6 в манифесте нет `ARDUINO_USB_CDC_ON_BOOT`, поэтому
    `Serial` был UART0 — `CMD:*` не доходил до приложения, а логи уходили в
    несоединённый UART-мост. Добавлены `ARDUINO_USB_MODE=1` и
    `ARDUINO_USB_CDC_ON_BOOT=1` в `[env:esp32-c6]`.
  - Найдено: `Provisioning::startAndWait()` блокировал `loop()`, поэтому USB
    не отвечал до Wi-Fi. В цикл ожидания добавлен `serialCmdUpdate()`.
  - [x] USB-вкладка «Настройка»: COM7 открывается, `info`/`status` приходят
        (`1.2.4`, ESP32-C6, flash 16 МБ), зависания нет (CPU 0 с / 8 с).
  - [ ] Проверить с телефона: видна ли точка `Aeris-Setup-XXXX`
        (`http://192.168.4.1`), сохраняются ли Wi-Fi-креды; после подключения
        `MQTT: Connected to spe4naz.online:8883`.

- [ ] **Обновить токен в приложении.**
  - Новый `SIGNALING_TOKEN` — в `firmware/main_controller/include/secrets.h`.
  - Приложение → Настройки → **«Токен доступа (API)»** → «Применить».
  - MQTT-пароль приложения (`app`) не менялся.

- [ ] **Проверить NVS-провижининг на устройстве.**
  - После USB-прошивки: `MQTT: Connected to spe4naz.online:8883`.
  - `Aeris-Setup-XXXX` → `http://192.168.4.1`: поля MQTT/API сохраняются в NVS.
  - Убедиться, что для работы не нужны секреты, вкомпилированные в образ.

- [ ] **Опубликовать прошивку 1.2.4 в `/fw`.**
  - Только после успешной проверки на устройстве.
  - `powershell -File deploy/build_fw_release.ps1 -Publish`
  - Релиз без секретов собран и проверен: C3, S3 и C6.
  - Сейчас `/fw`: C3 — 1.2.2, C6 — 1.2.3; S3 не публиковался. Версия 1.2.4 не опубликована.

---

## P1 — важно

- [x] **USB-настройка на непровижиненном устройстве.**
  Сделано: `serialCmdUpdate()` вызывается в цикле ожидания провижининга
  (`provisioning.cpp`), а для C6 `Serial` переведён на USB-Serial/JTAG
  (`ARDUINO_USB_MODE=1`, `ARDUINO_USB_CDC_ON_BOOT=1`).
  Проверено: `CMD:info`/`CMD:status` отвечают, пока устройство ждёт Wi-Fi.

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

- [ ] **Решить, нужен ли USB CDC на ESP32-S3.**
  У `esp32-s3-devkitc-1` нет `ARDUINO_USB_CDC_ON_BOOT`, поэтому `Serial` —
  UART0 (порт моста). Если USB-настройка из приложения нужна через нативный
  USB, добавить `-DARDUINO_USB_MODE=1 -DARDUINO_USB_CDC_ON_BOOT=1`, как у C6.

- [ ] **Проверить Windows-сборку.**
  Установщик: `deploy/installer/output/aeris_setup_1.2.1.exe`
  SHA256 `5b3432e7a5c178bf7484a9b36d9cb8f571f8c59e263c470918d4d1f59092d309`.
  Портативная папка: `mobile_app/build/windows/x64/runner/Release/` (`aeris.exe`).
  Сборка: `powershell -File deploy/app_windows.ps1`.
  - [ ] Установка и запуск, проверка COM-портов и уведомлений.
  - [x] Подключение к плате на вкладке «Настройка»: порт открывается без
        зависания (проверено на COM7, CPU 0.03 с / 8 с, окно отвечает).
        Причина прежнего зависания: `SerialPortReader` + блокирующий `drain()`
        в UI-изоляте. Serial I/O вынесен в worker-изолят.
  - [ ] Статус/логи с платы: сейчас C6 в цикле перезагрузки
        (`No bootable app partitions`) — нужна USB-прошивка 16 МБ.
  - [ ] Проверить MQTT, OTA и экспорт CSV.
  - Установщик не подписан — Windows SmartScreen покажет предупреждение.

- [ ] **Проверить APK на реальном телефоне.**
  APK: `deploy/installer/output/aeris-monitor-1.2.1.apk`
  SHA256 `d82730748d9aea7691f3d161e870e6d8f05185778bd867b9b21128f70d0d5deb`.
  Версия 1.2.1 (versionCode 4), подписан ключом `aeris-release.jks`.
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
C:\Users\Spe4naz\.platformio\penv\Scripts\pio.exe run -e esp32-c6
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

# Web + APK + Windows
C:\flutter\flutter\bin\flutter.bat build web --release
powershell -NoProfile -ExecutionPolicy Bypass -File C:\IoTs\deploy\app_android.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\IoTs\deploy\app_windows.ps1

# Сайты (с VPS)
curl -s -o /dev/null -w '%{http_code}\n' https://spe4naz.online/
curl -s -o /dev/null -w '%{http_code}\n' https://spe4naz.online/api/v1/health
curl -s -o /dev/null -w '%{http_code}\n' https://shorkey.online/
```
