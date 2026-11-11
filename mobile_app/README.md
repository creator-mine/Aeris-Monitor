# Aeris Monitor

Мобильное и веб-приложение системы **Aeris Monitor** — модульного мониторинга
параметров окружающей среды на ESP32.

Один код на Android, iOS, браузер, Windows, Linux и macOS.

## Возможности

- живые показания датчиков и графики;
- управление устройствами и умным домом;
- настройка Wi-Fi устройства;
- обновление прошивки по воздуху (OTA);
- фоновые уведомления на Android.

## Запуск

```bash
flutter pub get
flutter run
```

## Сборка

```bash
flutter build apk --release      # Android APK
flutter build web --release      # веб-версия
flutter build windows            # Windows
```

Подробности — в корневом `README.md` и `PROJECT_OVERVIEW.md`.
