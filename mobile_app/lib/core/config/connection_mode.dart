enum ConnectionMode {
  auto,
  lanDirect,
  mqtt;

  String get label => switch (this) {
        ConnectionMode.auto => 'Авто',
        ConnectionMode.lanDirect => 'Прямое LAN',
        ConnectionMode.mqtt => 'Только MQTT',
      };
}

/// Process-wide switch for LAN discovery and direct HTTP/WebSocket access.
///
/// [SettingsProvider] sets it from [ConnectionMode]: "Только MQTT" disables
/// every LAN path, leaving MQTT as the only transport.
class LanPolicy {
  static bool enabled = true;
}

enum ActiveChannel { lan, mqtt, none }
