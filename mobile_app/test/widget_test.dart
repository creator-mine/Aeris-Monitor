import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iot_modular_app/app.dart';
import 'package:iot_modular_app/core/api/api_client.dart';
import 'package:iot_modular_app/core/api/mqtt_client.dart';
import 'package:iot_modular_app/features/settings/providers/settings_provider.dart';

void main() {
  testWidgets('App should render', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsProvider = SettingsProvider();
    await settingsProvider.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settingsProvider),
          Provider.value(value: ApiClient()),
          Provider.value(value: MqttService()),
        ],
        child: const IoTApp(),
      ),
    );

    expect(find.text('Главная'), findsOneWidget);
  });
}
