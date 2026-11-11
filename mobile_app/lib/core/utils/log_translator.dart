import '../config/log_mode.dart';

/// Rules map a firmware log message to a short localized rendering.
///
/// The device keeps the canonical English messages ("Connected to MTS_136",
/// "Mount failed") in its ring buffer; the app translates known phrases at
/// display time ("облегчённый режим"). Unknown messages pass through
/// unchanged so they stay debuggable.
class LogTranslator {
  LogTranslator._();

  static final List<_Rule> _ruRules = [
    // ---- WiFi ----
    _Rule(r'^Connected to (.+)$', 'Подключено к \$1', tag: 'WiFi'),
    _Rule(r'^Reconnected$', 'Переподключено', tag: 'WiFi'),
    _Rule(
      r'^Connection lost, reconnecting\.\.\.$',
      'Соединение потеряно, переподключение...',
      tag: 'WiFi',
    ),
    _Rule(
      r'^\w+ saved credentials \(ssid=(.+)\), reconnecting$',
      'Учётные данные сохранены (\$1), переподключение',
      tag: 'WiFi',
    ),
    _Rule(
      r'^Credentials saved \(ssid=(.+)\), reconnecting$',
      'Учётные данные сохранены (\$1), переподключение',
      tag: 'WiFi',
    ),
    _Rule(
      r'^\w+ saved credentials \(ssid=(.+)\)$',
      'Учётные данные сохранены (\$1)',
      tag: 'WiFi',
    ),
    _Rule(r'^Credentials cleared by serial command$', 'Учётные данные очищены',
        tag: 'WiFi'),
    _Rule(
      r'^Config mode: AP (.+), http://.+$',
      'Режим настройки: AP \$1',
      tag: 'WiFi',
    ),

    // ---- MQTT ----
    _Rule(r'^Connected to .+:\d+$', 'Подключено', tag: 'MQTT'),
    _Rule(r'^Connect failed rc=(\d+)$', 'Ошибка подключения (код \$1)',
        tag: 'MQTT'),
    _Rule(r'^Reconnected$', 'Переподключено', tag: 'MQTT'),
    _Rule(
      r'^Connection lost, reconnecting\.\.\.$',
      'Соединение потеряно, переподключение...',
      tag: 'MQTT',
    ),
    _Rule(r'^enabled by serial command$', 'Включён', tag: 'MQTT'),
    _Rule(r'^disabled by serial command$', 'Отключён', tag: 'MQTT'),

    // ---- NTP ----
    _Rule(r'^Time synced .+$', 'Время синхронизировано', tag: 'NTP'),

    // ---- SD ----
    _Rule(r'^Mount failed$', 'Карта не обнаружена', tag: 'SD'),
    _Rule(r'^Mounted, (\d+) MB total$', 'Карта смонтирована, \$1 МБ',
        tag: 'SD'),

    // ---- Boot ----
    _Rule(r'^Active modules: (\d+)$', 'Активных модулей: \$1', tag: 'Boot'),
    _Rule(
      r'^Firmware (.+) starting \(chip (\d+) MHz, (\d+) MB flash\)$',
      'Прошивка \$1 запускается (чип \$2 МГц, \$3 МБ флеш)',
      tag: 'Boot',
    ),
    _Rule(r'^Firmware (.+) ready$', 'Прошивка \$1 готова', tag: 'Boot'),

    // ---- UART ----
    _Rule(r'^Too many modules!$', 'Слишком много модулей!', tag: 'UART'),
    _Rule(
      r'^Module (\d+) registered: (\d+) sensor\(s\), (\d+) metric\(s\)$',
      'Модуль \$1 зарегистрирован: \$2 датчика, \$3 метрики',
      tag: 'UART',
    ),
    _Rule(
      r'^Unknown cmd 0x([0-9A-Fa-f]{2}) from module (\d+)$',
      'Неизвестная команда 0x\$1 от модуля \$2',
      tag: 'UART',
    ),

    // ---- Signaling ----
    _Rule(r'^POST (.+) -> HTTP (\d+)$', 'POST \$1 → HTTP \$2',
        tag: 'Signaling'),
    _Rule(r'^Registered with server$', 'Зарегистрировано на сервере',
        tag: 'Signaling'),
    _Rule(r'^Register failed$', 'Ошибка регистрации', tag: 'Signaling'),
    _Rule(r'^WiFi lost, device offline$', 'Wi-Fi потерян, устройство офлайн',
        tag: 'Signaling'),
    _Rule(r'^Heartbeat failed, re-register$', 'Сбой heartbeat, повторная регистрация',
        tag: 'Signaling'),

    // ---- OTA ----
    _Rule(r'^HTTPS connect failed for (.+)$', 'Не удалось соединиться с \$1',
        tag: 'OTA'),
    _Rule(r'^No HTTP response \(timeout\) for (.+)$',
        'Нет ответа сервера (таймаут): \$1', tag: 'OTA'),
    _Rule(r'^HTTP error for (.+): (.+)$', 'Ошибка HTTP \$2 (\$1)', tag: 'OTA'),
    _Rule(r'^Update requested \((.+)\)$', 'Обновление запрошено (\$1)',
        tag: 'OTA'),
    _Rule(r'^Starting update \((.+)\)$', 'Запуск обновления (\$1)',
        tag: 'OTA'),
    _Rule(
      r'^Already up to date \((.+) == (.+)\), skipping$',
      'Актуальная версия, обновление пропущено',
      tag: 'OTA',
    ),
    _Rule(r'^Updating (.+) -> (.+)$', 'Обновление \$1 → \$2', tag: 'OTA'),
    _Rule(r'^No version manifest, downloading (.+)$', 'Нет манифеста, загрузка \$1',
        tag: 'OTA'),
    _Rule(r'^HTTPS connect failed$', 'Не удалось соединиться (HTTPS)',
        tag: 'OTA'),
    _Rule(r'^No HTTP response \(timeout\)$', 'Нет ответа сервера (таймаут)',
        tag: 'OTA'),
    _Rule(r'^HTTP error: (.+)$', 'Ошибка HTTP: \$1', tag: 'OTA'),
    _Rule(r'^Bad content length: (\d+)$', 'Неверная длина: \$1', tag: 'OTA'),
    _Rule(r'^Update.begin failed: (.+)$', 'Ошибка начала обновления: \$1',
        tag: 'OTA'),
    _Rule(r'^Downloading (\d+) bytes\.\.\.$', 'Загрузка \$1 байт...',
        tag: 'OTA'),
    _Rule(r'^Short download: (\d+)/(\d+)$', 'Неполная загрузка: \$1/\$2',
        tag: 'OTA'),
    _Rule(r'^SHA-256 mismatch, aborting$', 'Контрольная сумма не совпала, отмена',
        tag: 'OTA'),
    _Rule(r'^Update.end failed: (.+)$', 'Ошибка завершения обновления: \$1',
        tag: 'OTA'),
    _Rule(r'^Success! Rebooting\.\.\.$', 'Успех! Перезагрузка...', tag: 'OTA'),

    // ---- Sensor ----
    _Rule(r'^(.+) detected at 0x([0-9A-Fa-f]+)$', '\$1 обнаружен (адрес 0x\$2)',
        tag: 'Sensor'),
    _Rule(
      r'^Module lost: (.+) at 0x([0-9A-Fa-f]+)$',
      'Модуль потерян: \$1 (адрес 0x\$2)',
      tag: 'Sensor',
    ),
  ];

  /// Translate `msg` for display in `lightweight` mode using the app
  /// `language` ('ru' → Russian; anything else is left as-is).
  static String display(
    LogMode mode,
    String language,
    String tag,
    String msg,
  ) {
    if (mode != LogMode.lightweight) return msg;
    if (!language.toLowerCase().startsWith('ru')) return msg;
    for (final rule in _ruRules) {
      if (rule.tag != null && rule.tag != tag) continue;
      final match = rule.re.firstMatch(msg);
      if (match != null) {
        return _substitute(match, rule.replacement);
      }
    }
    return msg;
  }

  static String _substitute(Match match, String template) {
    return template.replaceAllMapped(
      RegExp(r'\$(\d+)'),
      (m) => match.group(int.parse(m.group(1)!)) ?? '',
    );
  }
}

class _Rule {
  _Rule(this.pattern, this.replacement, {this.tag});
  final String pattern;
  final String replacement;
  final String? tag;
  late final RegExp re = RegExp(pattern);
}