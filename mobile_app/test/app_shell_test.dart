import 'package:aeris/app.dart';
import 'package:aeris/core/api/local_device_service.dart';
import 'package:aeris/core/api/mqtt_client.dart';
import 'package:aeris/core/api/signaling_api.dart';
import 'package:aeris/features/dashboard/providers/dashboard_provider.dart';
import 'package:aeris/features/settings/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shell uses a rail on desktop and bottom tabs on a phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({'dark_mode': true});
    final settings = SettingsProvider(secrets: FakeSecretStore());
    await settings.init();

    final dashboard = DashboardProvider(
      signalingApi: SignalingApi(baseUrl: 'http://127.0.0.1:1/api/v1'),
      localDevices: LocalDeviceService(
        probe: (_, __) async => null,
        scan: () async => const [],
      ),
    );

    addTearDown(() {
      dashboard.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: dashboard),
          Provider.value(value: MqttService()),
        ],
        child: const IoTApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Ещё'), findsOneWidget);

    // Let the initial registry request and its short timeout finish.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
