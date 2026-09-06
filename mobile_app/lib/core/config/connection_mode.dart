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

enum ActiveChannel { lan, mqtt, none }