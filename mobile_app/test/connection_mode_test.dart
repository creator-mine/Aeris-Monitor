import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aeris/core/config/connection_mode.dart';
import 'package:aeris/core/security/secret_store.dart';
import 'package:aeris/features/settings/providers/settings_provider.dart';

import 'support/fake_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings persist and restore connection mode', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeSecretStore();
    final settings = SettingsProvider(secrets: store);
    await settings.init();
    expect(settings.connectionMode, ConnectionMode.auto);

    await settings.setConnectionMode(ConnectionMode.mqtt);
    expect(settings.connectionMode, ConnectionMode.mqtt);

    final restored = SettingsProvider(secrets: store);
    await restored.init();
    expect(restored.connectionMode, ConnectionMode.mqtt);
  });

  test('unknown stored mode falls back to auto', () async {
    SharedPreferences.setMockInitialValues({'connection_mode': 'bogus'});
    final settings = SettingsProvider(secrets: FakeSecretStore());
    await settings.init();
    expect(settings.connectionMode, ConnectionMode.auto);
  });

  test('MQTT-only mode disables every LAN path', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SettingsProvider(secrets: FakeSecretStore());
    await provider.init();
    expect(LanPolicy.enabled, isTrue);

    await provider.setConnectionMode(ConnectionMode.mqtt);
    expect(LanPolicy.enabled, isFalse);

    await provider.setConnectionMode(ConnectionMode.auto);
    expect(LanPolicy.enabled, isTrue);
  });

  test('stored MQTT-only mode restores the LAN policy on startup', () async {
    SharedPreferences.setMockInitialValues({'connection_mode': 'mqtt'});
    final provider = SettingsProvider(secrets: FakeSecretStore());
    await provider.init();

    expect(provider.connectionMode, ConnectionMode.mqtt);
    expect(LanPolicy.enabled, isFalse);
  });

  test('mqtt credentials persist and fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeSecretStore();
    final settings = SettingsProvider(secrets: store);
    await settings.init();
    expect(settings.mqttUsername.isNotEmpty, true);
    // Live secret is never baked in: the user must enter it in Настройки.
    expect(settings.mqttPassword, '');
    expect(store.values.containsKey(mqttPasswordSecretKey), isFalse);

    await settings.setMqttUsername('app');
    await settings.setMqttPassword('secret');

    // The password is kept in secure storage, not in SharedPreferences.
    expect(store.values[mqttPasswordSecretKey], 'secret');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(mqttPasswordSecretKey), isNull);

    final restored = SettingsProvider(secrets: store);
    await restored.init();
    expect(restored.mqttUsername, 'app');
    expect(restored.mqttPassword, 'secret');
  });

  test('migrates the plaintext MQTT password into secure storage', () async {
    SharedPreferences.setMockInitialValues({mqttPasswordSecretKey: 'legacy'});
    final store = FakeSecretStore();
    final settings = SettingsProvider(secrets: store);
    await settings.init();

    expect(settings.mqttPassword, 'legacy');
    expect(store.values[mqttPasswordSecretKey], 'legacy');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(mqttPasswordSecretKey), isNull);
  });

  test('secure value wins over a leftover plaintext copy', () async {
    SharedPreferences.setMockInitialValues({mqttPasswordSecretKey: 'old'});
    final store = FakeSecretStore({mqttPasswordSecretKey: 'new'});
    final settings = SettingsProvider(secrets: store);
    await settings.init();

    expect(settings.mqttPassword, 'new');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(mqttPasswordSecretKey), isNull);
  });
}
