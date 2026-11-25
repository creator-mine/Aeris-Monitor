import 'package:aeris/core/api/signaling_api.dart';
import 'package:aeris/features/charts/charts_screen.dart';
import 'package:aeris/features/charts/providers/charts_provider.dart';
import 'package:aeris/features/dashboard/providers/dashboard_provider.dart';
import 'package:aeris/features/settings/providers/settings_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:aeris/models/sensor_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_secret_store.dart';

/// Skips the real history request; the test supplies its own series.
class _TestChartsProvider extends ChartsProvider {
  @override
  Future<void> loadData() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(ChartsProvider provider, {SettingsProvider? settings}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ChartsProvider>.value(value: provider),
        ChangeNotifierProvider<DashboardProvider>.value(
          value: DashboardProvider(signalingApi: SignalingApi()),
        ),
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings ?? SettingsProvider(secrets: FakeSecretStore()),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData.dark(),
        home: const ChartsScreen(),
      ),
    );
  }

  testWidgets('normal chart mode renders without exception', (tester) async {
    final provider = ChartsProvider();
    provider.setSelectedDevice(
      'test_s3',
      metrics: const [
        MetricInfo(key: 'illuminance', name: 'Освещённость', unit: 'lux'),
      ],
    );

    final now = DateTime.now();
    final points = List.generate(52, (i) {
      return SensorDataPoint(
        timestamp: now.subtract(Duration(minutes: 51 - i)),
        value: 5.0 + (i % 7),
      );
    });
    provider.setChartDataForTest(
      'illuminance',
      SensorDataSeries(sensorType: 'illuminance', unit: 'lux', points: points),
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final error = tester.takeException();
    // ignore: avoid_print
    if (error != null) print('CHART ERROR: $error');
    expect(error, isNull);
  });

  testWidgets('shows every known parameter and marks missing sensors',
      (tester) async {
    final provider = ChartsProvider();
    provider.setSelectedDevice(
      'test_s3',
      metrics: const [
        MetricInfo(key: 'illuminance', name: 'Освещённость', unit: 'lux'),
      ],
    );

    await tester.pumpWidget(wrap(provider));
    await tester.pump();

    expect(find.text('Температура'), findsOneWidget);
    expect(find.text('Влажность'), findsOneWidget);
    expect(find.text('Давление'), findsOneWidget);
    expect(find.text('Газ'), findsNothing);
    expect(find.text('Освещённость'), findsOneWidget);

    await tester.tap(find.text('Температура'));
    await tester.pump();

    expect(find.text('Датчик не подключён'), findsOneWidget);
  });

  testWidgets('pressure stats follow the selected display unit',
      (tester) async {
    SharedPreferences.setMockInitialValues({'pressure_unit': 'kpa'});
    final settings = SettingsProvider(secrets: FakeSecretStore());
    await settings.init();

    final provider = _TestChartsProvider();
    provider.setSelectedDevice(
      'test_s3',
      metrics: const [
        MetricInfo(key: 'pressure', name: 'Давление', unit: 'hPa'),
      ],
    );
    final now = DateTime.now();
    provider.setChartDataForTest(
      'pressure',
      SensorDataSeries(
        sensorType: 'pressure',
        unit: 'hPa',
        points: [
          SensorDataPoint(
            timestamp: now.subtract(const Duration(minutes: 2)),
            value: 1000.0,
          ),
          SensorDataPoint(
            timestamp: now.subtract(const Duration(minutes: 1)),
            value: 1002.0,
          ),
        ],
      ),
    );

    await tester.pumpWidget(wrap(provider, settings: settings));
    await tester.pump();

    // 1000 hPa = 100.0 kPa, 1002 hPa = 100.2 kPa, average 100.1 kPa.
    expect(find.text('100.0 кПа'), findsOneWidget);
    expect(find.text('100.1 кПа'), findsOneWidget);
    expect(find.text('100.2 кПа'), findsWidgets);
  });
}
