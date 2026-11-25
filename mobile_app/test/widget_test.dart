import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aeris/app.dart';
import 'package:aeris/core/api/api_client.dart';
import 'package:aeris/core/api/local_device_service.dart';
import 'package:aeris/core/api/mqtt_client.dart';
import 'package:aeris/core/api/signaling_api.dart';
import 'package:aeris/features/dashboard/providers/dashboard_provider.dart';
import 'package:aeris/features/settings/providers/settings_provider.dart';

import 'support/fake_secret_store.dart';

void main() {
  testWidgets('App should render', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider(secrets: FakeSecretStore());
    await settingsProvider.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settingsProvider),
          Provider.value(value: ApiClient()),
          Provider.value(value: MqttService()),
          ChangeNotifierProvider.value(
            value: DashboardProvider(
              signalingApi: SignalingApi(
                baseUrl: 'http://127.0.0.1:1/api/v1',
              ),
              localDevices: LocalDeviceService(
                probe: (_, __) async => null,
                scan: () async => const [],
              ),
            ),
          ),
        ],
        child: const IoTApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Главная'), findsOneWidget);
  });
}
