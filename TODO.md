# Aeris Monitor — TODO

> Обновлено **16.11.2026**. Только открытые задачи.
>
> **Приоритеты:** `P0` — блокер/безопасность, `P1` — важно, `P2` — улучшение.

## Текущее состояние

- **C6 `esp32c6_001`** — прошит по USB (factory 16 МБ), Wi-Fi `GGM-2G`
  (192.168.0.117), MQTT и API работают. Сейчас отключён от USB (офлайн).
  Датчиков и SD-карты нет.
- **S3 `esp32s3_001`** — прошит по USB 15.11.2026: **1.2.4** + USB CDC,
  MAC `14:c1:9f:36:7e:9c`, COM6. `verify-flash` — digest совпал.
  Онлайн: Wi-Fi `GGM-2G` (192.168.0.162, RSSI ≈ −75), MQTT
  `spe4naz.online:8883`, зарегистрирован на сервере. MQTT/API-доступы
  записаны в NVS из приложения.
- **C3** — до сих пор не перепрошит по USB после смены брокера (см. P0);
  в `/fw` для него уже лежит 1.2.4.
- **Приложение 1.2.1** — после перезагрузки платы (сохранение Wi-Fi,
  «Перезагрузить», OTA) само переподключает COM-порт; статус опрашивается
  каждые 5 с, логи — каждые 2 с. На Android вкладка «Настройка» заменена
  экраном «Wi-Fi»: провижининг с телефона через `192.168.4.1` без браузера.
- **Публикации `/fw`:** 1.2.4 для C3 (`main.bin`), C6 и S3 — выложены
  16.11.2026, хеши скачанных файлов совпали с локальными сборками.
- **Артефакты:** прошивка 1.2.4 (C3/C6/S3) без секретов; APK 1.2.1
  (`b2996e2b…`); установщик Windows 1.2.1 (`0c028463…`).

---

## P0 — критично

- [ ] **Перепрошить ESP32-C3 по USB (однократно).**
  Плата работает на 1.2.2, где в образе зашит старый брокер `2.26.98.234`.
  OTA подтянет 1.2.4, но в этой сборке креды берутся только из NVS, поэтому
  без USB-прошивки устройство может уйти в офлайн.
  - `powershell -File deploy/flash_device.ps1 -Environment esp32-c3 -Port COMx`
  - Критерий: в логе `MQTT: Connected to spe4naz.online:8883`, устройство онлайн.
  - Скрипт сохраняет NVS; `-EraseAll` — только для чистой платы.
  - После прошивки сверить образ:
    `verify-flash 0x10000 .pio/build/esp32-c3/firmware.bin`
    (sha256 `f5ed856c…`).

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

- [ ] **Веб-панель: смириться с потерей исходников или переписать с нуля.**
  В `server/web` только собранный `dist` (Vue + Vite, минифицированный
  `index-BrOYRvFz.js` ≈ 1,1 МБ) **без sourcemap**; в git исходников панели
  никогда не было, на диске копий тоже нет. Восстановить код нельзя.
  - Сейчас панель работает: `https://spe4naz.online/panel/` → 200.
  - Варианты: переписать панель на текущем API (отдельная задача) либо
    оставить `dist` как единственный артефакт и убрать `build:panel`
    из пайплайна.

- [ ] **Проверить APK на телефоне (TLS, уведомления, OTA, CSV).**
  APK: `deploy/installer/output/aeris-monitor-1.2.1.apk`
  SHA256 `b2996e2bcbe253e66114b0accb0a8d6bda6d9b0630d6764e36ddd45675b43103`,
  versionCode 4, ключ `aeris-release.jks`.
  - Установка из неизвестного источника.
  - MQTT `8883` TLS и фоновые уведомления при закрытом приложении.
  - OTA-кнопки (`ota`/`rollback`/`restart`), CSV через «Поделиться».
  - Вкладка «Wi-Fi»: подключиться к `Aeris-Setup-XXXX`, ввести домашнюю сеть,
    проверить, что устройство перезагрузилось и ушло в рабочую сеть.
  - Уведомление «Слежу за устройствами» больше не всплывает каждую минуту;
    выключатель в «Настройки» → «Фоновая работа» убирает его сразу.

---

## P2 — улучшения

- [ ] **Проверить установщик Windows.**
  `deploy/installer/output/aeris_setup_1.2.1.exe`
  SHA256 `0c028463998e88bf2ff70daad3873b5867313b694bb939ef82ca7bfbebcad9ab`.
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
