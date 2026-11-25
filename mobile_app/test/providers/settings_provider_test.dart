import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aeris/core/config/pressure_unit.dart';
import 'package:aeris/features/settings/providers/settings_provider.dart';

import '../support/fake_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider OTA URL', () {
    test('effective OTA URL falls back to the API URL when empty', () async {
      SharedPreferences.setMockInitialValues({});
      final p = SettingsProvider(secrets: FakeSecretStore());
      await p.init();

      expect(p.otaUrl, '');
      expect(p.effectiveOtaUrl, p.apiUrl);

      await p.setApiUrl('http://192.168.1.10');
      expect(p.effectiveOtaUrl, 'http://192.168.1.10');
    });

    test('explicit OTA URL wins and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final p = SettingsProvider(secrets: FakeSecretStore());
      await p.init();

      await p.setOtaUrl('https://ota.example.com/');
      expect(p.otaUrl, 'https://ota.example.com/');
      expect(p.effectiveOtaUrl, 'https://ota.example.com/');

      final reloaded = SettingsProvider(secrets: FakeSecretStore());
      await reloaded.init();
      expect(reloaded.otaUrl, 'https://ota.example.com/');
      expect(reloaded.effectiveOtaUrl, 'https://ota.example.com/');
    });

    test('blank OTA URL resets to the API URL fallback', () async {
      SharedPreferences.setMockInitialValues(
          {'ota_url': 'https://x.example.com'});
      final p = SettingsProvider(secrets: FakeSecretStore());
      await p.init();

      await p.setOtaUrl('   ');
      expect(p.effectiveOtaUrl, p.apiUrl);
    });
  });

  group('SettingsProvider LAN address', () {
    test('defaults to empty and persists the manual host', () async {
      SharedPreferences.setMockInitialValues({});
      final p = SettingsProvider(secrets: FakeSecretStore());
      await p.init();
      expect(p.deviceHost, '');

      await p.setDeviceHost(' 192.168.4.1 ');
      expect(p.deviceHost, '192.168.4.1');

      final reloaded = SettingsProvider(secrets: FakeSecretStore());
      await reloaded.init();
      expect(reloaded.deviceHost, '192.168.4.1');
    });
  });

  group('SettingsProvider pressure unit', () {
    test('defaults to hPa and persists the selection', () async {
      SharedPreferences.setMockInitialValues({});
      final p = SettingsProvider(secrets: FakeSecretStore());
      await p.init();
      expect(p.pressureUnit, PressureUnit.hpa);

      await p.setPressureUnit(PressureUnit.kpa);
      expect(p.pressureUnit, PressureUnit.kpa);

      final reloaded = SettingsProvider(secrets: FakeSecretStore());
      await reloaded.init();
      expect(reloaded.pressureUnit, PressureUnit.kpa);
    });

    test('unknown stored value falls back to hPa', () async {
      SharedPreferences.setMockInitialValues({'pressure_unit': 'bar'});
      final p = SettingsProvider(secrets: FakeSecretStore());
      await p.init();
      expect(p.pressureUnit, PressureUnit.hpa);
    });
  });
}
