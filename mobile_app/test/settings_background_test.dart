import 'package:aeris/core/background/background_prefs.dart';
import 'package:aeris/features/settings/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('background monitor is on by default and its switch is persisted',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SettingsProvider();
    await provider.init();

    expect(provider.backgroundMonitor, isTrue,
        reason: 'existing installs keep the monitor enabled');

    await provider.setBackgroundMonitor(false);
    expect(provider.backgroundMonitor, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(backgroundMonitorPrefKey), isFalse);
  });

  test('a disabled monitor stays disabled after a restart', () async {
    SharedPreferences.setMockInitialValues({backgroundMonitorPrefKey: false});
    final provider = SettingsProvider();
    await provider.init();

    expect(provider.backgroundMonitor, isFalse);
  });
}
