import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iot_modular_app/core/config/connection_mode.dart';
import 'package:iot_modular_app/features/settings/providers/settings_provider.dart';

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
}