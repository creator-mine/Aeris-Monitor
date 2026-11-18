// ignore_for_file: prefer_single_quotes
import 'package:flutter/widgets.dart';

/// Lightweight runtime translation for the app UI.
///
/// Russian is the source language. English strings live in [_en] and are keyed
/// by the exact Russian literal, so screens can keep their readable text and
/// only wrap it with [TrText] or [of].
class L10n {
  static const List<Locale> supportedLocales = [
    Locale('ru'),
    Locale('en'),
  ];

  static String translate(String source, [String? languageCode]) {
    final code = (languageCode ?? 'ru').toLowerCase();
    if (!code.startsWith('en')) return source;
    return _en[source] ?? _translateDynamic(source) ?? source;
  }

  static String of(BuildContext context, String source) {
    return translate(source, Localizations.localeOf(context).languageCode);
  }

  /// Messages built with interpolated values cannot be looked up by an exact
  /// key. Handle the handful of shapes used across the app here.
  static String? _translateDynamic(String source) {
    if (source.endsWith(' онлайн')) {
      return '${source.substring(0, source.length - ' онлайн'.length)} online';
    }
    if (source.startsWith('Последнее обновление: ')) {
      return 'Last update: ${source.substring('Последнее обновление: '.length)}';
    }
    if (source.startsWith('Сравнение: ')) {
      return 'Comparison: ${source.substring('Сравнение: '.length)}';
    }
    if (source.startsWith('Загружено: ')) {
      return 'Uploaded: ${source.substring('Загружено: '.length)}';
    }
    if (source.startsWith('График сохранён: ')) {
      return 'Chart saved: ${source.substring('График сохранён: '.length)}';
    }
    if (source.startsWith('Логи сохранены: ')) {
      return 'Logs saved: ${source.substring('Логи сохранены: '.length)}';
    }
    if (source.startsWith('Собрано: ')) {
      return 'Built: ${source.substring('Собрано: '.length)}';
    }
    if (source.startsWith('Опубликованная v')) {
      return 'Published v${source.substring('Опубликованная v'.length)}';
    }
    if (source.startsWith('Прошивка v')) {
      return 'Firmware v${source.substring('Прошивка v'.length)}';
    }
    if (source.startsWith('История сборок (')) {
      return 'Build history (${source.substring('История сборок ('.length)}';
    }
    if (source.startsWith('Изменённые файлы (')) {
      return 'Changed files (${source.substring('Изменённые файлы ('.length)}';
    }
    if (source.startsWith('Изменения конфига (')) {
      return 'Config changes (${source.substring('Изменения конфига ('.length)}';
    }
    if (source.startsWith('Диагностика · ')) {
      return 'Diagnostics · ${source.substring('Диагностика · '.length)}';
    }
    if (source.startsWith('Устройство (')) {
      return 'Device (${source.substring('Устройство ('.length)}';
    }
    if (source.startsWith('Версия ') &&
        source.endsWith(' будет удалена навсегда.')) {
      final version = source.substring(
        'Версия '.length,
        source.length - ' будет удалена навсегда.'.length,
      );
      return 'Version $version will be deleted permanently.';
    }
    if (source.startsWith('Вы уверены, что хотите удалить "')) {
      return 'Delete ${source.substring('Вы уверены, что хотите удалить '.length)}?';
    }
    if (source.startsWith('Правило «')) {
      return 'Rule ${source.substring('Правило '.length)}';
    }
    if (source.startsWith('Команда «')) {
      return 'Command ${source.substring('Команда '.length)}';
    }
    if (source.contains(' записей')) {
      return source.replaceAll(' записей', ' entries');
    }
    if (source.contains(' д ') ||
        source.contains(' ч ') ||
        source.contains(' м ')) {
      return source
          .replaceAll(' д', ' d')
          .replaceAll(' ч', ' h')
          .replaceAll(' м', ' min')
          .replaceAll(' с', ' s');
    }

    if (source.startsWith('Прозрачность: ')) {
      return 'Opacity: ${source.substring('Прозрачность: '.length)}';
    }
    if (source.startsWith('сборка ')) {
      return 'build ${source.substring('сборка '.length)}';
    }
    if (source.startsWith('тип: ')) {
      return 'type: ${source.substring('тип: '.length)}';
    }
    if (source.startsWith('Пусто — автоматически (')) {
      return 'Empty — automatic (${source.substring('Пусто — автоматически ('.length)}';
    }
    if (source.startsWith('Не удалось получить данные: ')) {
      return 'Could not load data: ${source.substring('Не удалось получить данные: '.length)}';
    }
    if (source.startsWith('Ошибка экспорта: ')) {
      return 'Export error: ${source.substring('Ошибка экспорта: '.length)}';
    }
    if (source.startsWith('Не удалось открыть документацию: ')) {
      return 'Could not open the documentation: ${source.substring('Не удалось открыть документацию: '.length)}';
    }
    if (source.startsWith('Экспортировано: ')) {
      return 'Exported: ${source.substring('Экспортировано: '.length)}';
    }
    if (source.startsWith('firmware.bin готов (')) {
      return 'firmware.bin ready (${source.substring('firmware.bin готов ('.length)}';
    }
    final ota =
        RegExp(r'^Устройство "(.+)" скачает последнюю версию прошивки.*$');
    final otaMatch = ota.firstMatch(source);
    if (otaMatch != null) {
      return 'Device “${otaMatch.group(1)}” will download the latest firmware and reboot.';
    }
    final rollback =
        RegExp(r'^Устройство "(.+)" переключится на предыдущую версию.*$');
    final rollbackMatch = rollback.firstMatch(source);
    if (rollbackMatch != null) {
      return 'Device “${rollbackMatch.group(1)}” will switch to the previous firmware and reboot.';
    }
    if (source.startsWith('Файл для ') && source.contains(', а выбрано ')) {
      final separator = source.indexOf(', а выбрано ');
      final expected = source.substring('Файл для '.length, separator);
      final actual = source.substring(separator + ', а выбрано '.length);
      return 'The file is for $expected, but $actual was selected.';
    }

    final offline = RegExp(
        r'^Устройство «(.+)» офлайн\. Включите его или выберите онлайн-устройство в списке\.$');
    final match = offline.firstMatch(source);
    if (match != null) {
      return 'Device “${match.group(1)}” is offline. Power it on or choose an online device from the list.';
    }

    final missing = RegExp(r'^Устройство не сообщает параметр «(.+)»\.$');
    final missingMatch = missing.firstMatch(source);
    if (missingMatch != null) {
      return 'The device does not report “${missingMatch.group(1)}”.';
    }

    if (source.startsWith('Не удалось подключиться к ')) {
      final address = source.substring('Не удалось подключиться к '.length);
      final dot = address.indexOf('.');
      if (dot > 0) {
        final target = address.substring(0, dot);
        return 'Could not connect to $target. Make sure the device is powered on and on the same Wi-Fi network.';
      }
    }

    if (source.startsWith('Устройство «') && source.contains('» офлайн.')) {
      final name = source.substring('Устройство «'.length, source.indexOf('»'));
      return 'Device “$name” is offline.';
    }

    return null;
  }

  static const Map<String, String> _en = {
    "1. Вернитесь к домашней сети в настройках Wi-Fi телефона.\n":
        "1. Return to your home Wi-Fi network in the phone's Wi-Fi settings.\n",
    "COM-порт": "COM port",
    "esptool не найден. Установите PlatformIO и соберите проект хотя бы один раз.":
        "esptool not found. Install PlatformIO and build the project at least once.",
    "MQTT (необязательно)": "MQTT (optional)",
    "MQTT и API": "MQTT and API",
    "MQTT не подключён — команды недоступны.":
        "MQTT is not connected — commands are unavailable.",
    "PlatformIO не найден": "PlatformIO not found",
    "PlatformIO, папка проекта, версия и предпросмотр":
        "PlatformIO, project folder, version and preview",
    "platformio.ini не найден в выбранной папке":
        "platformio.ini was not found in the selected folder",
    "Акцентный цвет": "Accent colour",
    "Версия (x.y.z)": "Version (x.y.z)",
    "Версия сборки": "Build version",
    "Выберите COM-порт и нажмите «Подключиться»":
        "Select a COM port and press “Connect”",
    "Выберите изображение для фона приложения":
        "Choose an image for the app background",
    "Выберите порт": "Select a port",
    "Выберите устройство": "Select a device",
    "Выберите файл или вставьте ссылку — прошивка скачается сама. ":
        "Choose a file or paste a link — the firmware downloads automatically. ",
    "Выбрать .bin": "Choose .bin",
    "Выбрать изображение": "Choose image",
    "Выбрать папку проекта": "Choose project folder",
    "Графики": "Charts",
    "Датчик": "Sensor",
    "Датчик не подключён": "Sensor not connected",
    "Действие": "Action",
    "Диагностика": "Diagnostics",
    "Для одной из версий нет конфига": "No config for one of the versions",
    "Добавить правило": "Add rule",
    "Документация PlatformIO": "PlatformIO documentation",
    "Есть обновления": "Updates available",
    "Живые логи": "Live logs",
    "Загрузить": "Upload",
    "Загрузка данных...": "Loading data...",
    "Загрузка правил...": "Loading rules...",
    "Загрузка устройств...": "Loading devices...",
    "Заменить": "Replace",
    "Запустите проверку, чтобы убедиться в готовности окружения к сборке.":
        "Run the check to make sure the build environment is ready.",
    "Изменить": "Change",
    "Изменить порт": "Change port",
    "Или ID устройства вручную": "Or enter the device ID manually",
    "Имя сети (SSID)": "Network name (SSID)",
    "Информация о прошивке": "Firmware information",
    "Информация об устройстве": "Device information",
    "Исходный код": "Source code",
    "Команда скопирована в буфер обмена": "Command copied to clipboard",
    "Конфиг на момент сборки": "Config at build time",
    "Конфиг не сохранён для этой версии":
        "Config was not saved for this version",
    "Лог скопирован в буфер обмена": "Log copied to clipboard",
    "Логи пусты": "Logs are empty",
    "Логи пусты — ждём сообщений с устройства...":
        "Logs are empty — waiting for device messages...",
    "Логи устройства": "Device logs",
    "Модули не отвечают": "Modules are not responding",
    "Модули устройства": "Device modules",
    "Минимум": "Minimum",
    "Среднее": "Average",
    "Максимум": "Maximum",
    "Температура": "Temperature",
    "Влажность": "Humidity",
    "Давление": "Pressure",
    "Газ": "Gas",
    "Освещённость": "Illuminance",
    "1ч": "1h",
    "6ч": "6h",
    "24ч": "24h",
    "7д": "7d",
    "30д": "30d",
    "Онлайн": "Online",
    "Офлайн": "Offline",
    "Название": "Name",
    "Переименовать устройство": "Rename device",
    "Не удалось переименовать устройство": "Could not rename the device",
    "Например: 2.1.0": "Example: 2.1.0",
    "Например: esp32c3_001": "Example: esp32c3_001",
    "Например: relay:on": "Example: relay:on",
    "Например: Жара под потолком": "Example: Hot under the ceiling",
    "Настроить Wi-Fi": "Set up Wi-Fi",
    "Настроить ещё одно устройство": "Set up another device",
    "Настройка": "Setup",
    "Настройки": "Settings",
    "Настройки Wi-Fi телефона": "Phone Wi-Fi settings",
    "Не удалось открыть документацию": "Could not open the documentation",
    "Недопустимый формат версии": "Invalid version format",
    "Нет данных для отображения": "No data to display",
    "Нет данных для сравнения": "No data to compare",
    "Нет данных для экспорта": "No data to export",
    "Нет подключённых устройств": "No connected devices",
    "Нет правил": "No rules",
    "Нет сохранённых сборок": "No saved builds",
    "Нет устройств": "No devices",
    "Нет устройств в реестре": "No devices in the registry",
    "Нужен образ приложения .bin (OTA), не merged/factory":
        "An app .bin image (OTA) is required, not merged/factory",
    "Облегчённый": "Lightweight",
    "Обновить": "Refresh",
    "Обновить прошивку": "Update firmware",
    "Обновить прошивку?": "Update firmware?",
    "Обновить список портов": "Refresh port list",
    "обновление": "update",
    "Обновление по воздуху": "Over-the-air update",
    "Опубликованная версия (OTA)": "Published version (OTA)",
    "Остановить сравнение": "Stop comparison",
    "Откатить": "Roll back",
    "Откатить прошивку": "Roll back firmware",
    "Откатить прошивку?": "Roll back firmware?",
    "Отключиться": "Disconnect",
    "Открыть настройки Wi-Fi": "Open Wi-Fi settings",
    "Отмена": "Cancel",
    "Отменить скачивание": "Cancel download",
    "Очистить": "Clear",
    "Панель управления": "Dashboard",
    "Параметры среды (platformio.ini)": "Environment settings (platformio.ini)",
    "Пароль": "Password",
    "Пароль MQTT": "MQTT password",
    "Пауза": "Pause",
    "Перезагрузить": "Restart",
    "Переключить": "Switch",
    "Перерыв между срабатываниями, секунд":
        "Cooldown between triggers, seconds",
    "по умолчанию: device": "default: device",
    "Повторить": "Retry",
    "Подключение к Wi-Fi": "Connecting to Wi-Fi",
    "Подключение по USB": "USB connection",
    "Подключите ESP32 по USB": "Connect the ESP32 over USB",
    "Подключите плату и выберите COM-порт выше.":
        "Connect the board and select the COM port above.",
    "Пользователь MQTT": "MQTT user",
    "Порог": "Threshold",
    "Применить и переподключиться": "Apply and reconnect",
    "Проверить на сайте": "Check on the website",
    "Проверить обновления": "Check for updates",
    "Проверить связь с устройством": "Check connection to the device",
    "Проверка актуальной версии на сайте...":
        "Checking the latest version on the website...",
    "Проверки перед сборкой": "Pre-build checks",
    "Проверяю связь с 192.168.4.1...": "Checking connection to 192.168.4.1...",
    "Произошла ошибка": "An error occurred",
    "Прошивка": "Firmware",
    "пусто — не менять": "empty — keep unchanged",
    "Пустые поля оставляют текущие значения устройства":
        "Empty fields keep the device's current values",
    "Путь к прошивке не сохранён": "Firmware path was not saved",
    "Путь скопирован в буфер обмена": "Path copied to clipboard",
    "Режим соединения": "Connection mode",
    "Русский": "Russian",
    "Сборка из исходников": "Build from source",
    "Сбросить": "Reset",
    "Сбросить Wi-Fi": "Reset Wi-Fi",
    "Сбросить версию (авто)": "Reset version (auto)",
    "Скачать": "Download",
    "Скопировать команду": "Copy command",
    "Скопировать лог": "Copy log",
    "Скопировать путь": "Copy path",
    "Создайте правило: при превышении порога\nотправить команду или уведомить":
        "Create a rule: when the threshold is exceeded,\nsend a command or notify",
    "Сохранить": "Save",
    "Сохранить доступы": "Save credentials",
    "Сравнить": "Compare",
    "Сравнить устройства": "Compare devices",
    "Ссылка на .bin или GitHub": ".bin or GitHub link",
    "Стандартный": "Standard",
    "Тайм-аут опроса порта. Проверьте соединение и попробуйте ещё раз.":
        "Port polling timed out. Check the connection and try again.",
    "Триггер": "Trigger",
    "Убрать": "Remove",
    "Удалить": "Delete",
    "Удалить правило?": "Delete rule?",
    "Удалить сборку?": "Delete build?",
    "Удалить устройство?": "Delete device?",
    "Умный дом": "Smart home",
    "Установите PlatformIO, чтобы собирать и заливать прошивки.":
        "Install PlatformIO to build and upload firmware.",
    "Устройства": "Devices",
    "Устройства не обнаружены. Подключите ESP32 по USB.":
        "No devices found. Connect the ESP32 over USB.",
    "Устройства регистрируются автоматически\nпри подключении к сети":
        "Devices register automatically\nwhen they join the network",
    "Устройство": "Device",
    "Устройство настроено": "Device configured",
    "Устройство перезагружается, переподключаюсь...":
        "Device is restarting, reconnecting...",
    "Устройство работает в диапазоне 2,4 ГГц.":
        "The device operates on the 2.4 GHz band.",
    "Устройство скачает прошивку само. USB и сборка не нужны.":
        "The device downloads the firmware itself. No USB or build required.",
    "Файл firmware.bin не найден": "firmware.bin not found",
    "Файл не найден": "File not found",
    "Фон не выбран": "No background selected",
    "Экспорт": "Export",
    "Экспорт CSV": "Export CSV",
    "Экспорт доступен только в настольной версии":
        "Export is only available in the desktop version",
    "Экспорт прошивки доступен только в настольной версии":
        "Firmware export is only available in the desktop version",
    "Главная": "Home",
    "На телефоне настройка по USB недоступна. Подключитесь к точке доступа устройства (Aeris-Setup-XXXX) и откройте http://192.168.4.1, либо настройте Wi-Fi с компьютера.":
        "USB setup is not available on a phone. Connect to the device access point (Aeris-Setup-XXXX) and open http://192.168.4.1, or configure Wi-Fi from a computer.",
    "Доступы сохраняются в NVS на устройстве и в приложение не передаются. Пустые поля остаются без изменений; пароль вводится заново при каждой смене.":
        "Credentials are stored in the device NVS and are not sent to the app. Empty fields stay unchanged; the password is re-entered on every change.",
    "Точка доступа устройства работает около 5 минут и поднимается снова после каждой перезагрузки без сохранённой сети.":
        "The device's access point stays up for about 5 minutes and returns after every reboot without a saved network.",
    "Выберите firmware.bin, собранный PlatformIO, или OTA-образ с сервера/GitHub. Полный merged-образ с bootloader не подходит.":
        "Choose a firmware.bin built by PlatformIO, or an OTA image from the server/GitHub. A full merged image with bootloader is not suitable.",
    "В облегчённом режиме известные системные события показываются краткими переведёнными фразами.":
        "In lightweight mode, known system events are shown as short translated phrases.",
    "Постоянное уведомление нужно Android, чтобы события правил приходили при закрытом приложении. Выключите — уведомление исчезнет, фоновый мониторинг остановится.":
        "Android needs the persistent notification so rule events arrive while the app is closed. Turn it off and the notification disappears and background monitoring stops.",
    "Язык интерфейса": "Interface language",
    "Переключает язык интерфейса и перевод логов.":
        "Switches the interface language and log translation.",
    "Язык логов": "Log language",
  };
}
