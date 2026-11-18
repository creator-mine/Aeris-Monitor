import 'package:aeris/features/charts/charts_screen.dart';
import 'package:aeris/features/charts/providers/charts_provider.dart';
import 'package:aeris/models/device.dart';
import 'package:aeris/models/sensor_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    await tester.pumpWidget(
      ChangeNotifierProvider<ChartsProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const ChartsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final error = tester.takeException();
    // ignore: avoid_print
    if (error != null) print('CHART ERROR: $error');
    expect(error, isNull);
  });
}
