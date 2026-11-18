import 'package:aeris/core/api/signaling_api.dart';
import 'package:aeris/features/charts/charts_screen.dart';
import 'package:aeris/features/charts/providers/charts_provider.dart';
import 'package:aeris/features/dashboard/providers/dashboard_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:aeris/models/sensor_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(ChartsProvider provider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ChartsProvider>.value(value: provider),
        ChangeNotifierProvider<DashboardProvider>.value(
          value: DashboardProvider(signalingApi: SignalingApi()),
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
    expect(find.text('Газ'), findsOneWidget);
    expect(find.text('Освещённость'), findsOneWidget);

    await tester.tap(find.text('Температура'));
    await tester.pump();

    expect(find.text('Датчик не подключён'), findsOneWidget);
  });
}
