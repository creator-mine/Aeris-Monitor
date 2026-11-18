import 'package:aeris/core/api/provisioning_api.dart';
import 'package:aeris/features/provisioning/provisioning_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the device's http://192.168.4.1 endpoint.
class _FakeProvisioningApi extends ProvisioningApi {
  _FakeProvisioningApi({this.reachable = true, this.saveError});

  bool reachable;
  String? saveError;
  Map<String, String>? lastSave;
  int saveCalls = 0;

  @override
  Future<bool> probe() async => reachable;

  @override
  Future<String?> save({
    required String ssid,
    required String password,
    String mqttUser = '',
    String mqttPassword = '',
  }) async {
    saveCalls++;
    lastSave = {
      'ssid': ssid,
      'password': password,
      'mqtt_user': mqttUser,
      'mqtt_password': mqttPassword,
    };
    return saveError;
  }
}

Future<void> _pump(WidgetTester tester, ProvisioningApi api) async {
  // A tall surface so the whole form (including the save button) is laid out.
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ProvisioningScreen(api: api),
  ));
  await tester.pump(); // post-frame probe
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('shows the setup steps and detects the device', (tester) async {
    final api = _FakeProvisioningApi();
    await _pump(tester, api);

    expect(find.text('Первичное подключение'), findsOneWidget);
    expect(find.text('Домашний Wi-Fi'), findsOneWidget);
    expect(find.text('Устройство найдено (192.168.4.1)'), findsOneWidget);
  });

  testWidgets('warns when the phone is not on the device AP', (tester) async {
    final api = _FakeProvisioningApi(reachable: false);
    await _pump(tester, api);

    expect(
      find.textContaining('Устройство не найдено'),
      findsOneWidget,
    );
  });

  testWidgets('requires an SSID before saving', (tester) async {
    final api = _FakeProvisioningApi();
    await _pump(tester, api);

    final button = find.text('Сохранить и перезагрузить');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('Введите имя домашней сети (SSID)'), findsOneWidget);
    expect(api.saveCalls, 0);
  });

  testWidgets('saves the credentials and shows success', (tester) async {
    final api = _FakeProvisioningApi();
    await _pump(tester, api);

    await tester.enterText(
        find.widgetWithText(TextField, 'Имя сети (SSID)'), 'GGM-2G');
    await tester.enterText(
        find.widgetWithText(TextField, 'Пароль'), 'secret-pass');

    final button = find.text('Сохранить и перезагрузить');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.lastSave?['ssid'], 'GGM-2G');
    expect(api.lastSave?['password'], 'secret-pass');
    expect(find.text('Устройство настроено'), findsOneWidget);
    expect(find.textContaining('GGM-2G'), findsOneWidget);
  });

  testWidgets('shows the device error when saving fails', (tester) async {
    final api = _FakeProvisioningApi(saveError: 'nvs_write_failed');
    await _pump(tester, api);

    await tester.enterText(
        find.widgetWithText(TextField, 'Имя сети (SSID)'), 'GGM-2G');
    final button = find.text('Сохранить и перезагрузить');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.textContaining('Не удалось сохранить данные'), findsOneWidget);
    expect(find.text('Устройство настроено'), findsNothing);
  });
}
