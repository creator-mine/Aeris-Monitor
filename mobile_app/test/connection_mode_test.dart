import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aeris/core/config/connection_mode.dart';
import 'package:aeris/features/settings/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings persist and restore connection mode', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    expect(settings.connectionMode, ConnectionMode.auto);

    await settings.setConnectionMode(ConnectionMode.mqtt);
    expect(settings.connectionMode, ConnectionMode.mqtt);

    final restored = SettingsProvider();
    await restored.init();
    expect(restored.connectionMode, ConnectionMode.mqtt);
  });

  test('unknown stored mode falls back to auto', () async {
    SharedPreferences.setMockInitialValues({'connection_mode': 'bogus'});
    final settings = SettingsProvider();
    await settings.init();
    expect(settings.connectionMode, ConnectionMode.auto);
  });

  test('mqtt credentials persist and fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsProvider();
    await settings.init();
    expect(settings.mqttUsername.isNotEmpty, true);
    // Live secret is never baked in: the user must enter it in Настройки.
    expect(settings.mqttPassword, '');
    expect(settings.signalingToken, '');

    await settings.setMqttUsername('app');
    await settings.setMqttPassword('secret');
    await settings.setSignalingToken('tok-123');

    final restored = SettingsProvider();
    await restored.init();
    expect(restored.mqttUsername, 'app');
    expect(restored.mqttPassword, 'secret');
    expect(restored.signalingToken, 'tok-123');
  });
}