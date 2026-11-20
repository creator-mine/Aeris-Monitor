import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aeris/shared/theme/app_theme.dart';
import 'package:aeris/shared/widgets/segmented_toggle.dart';

Widget _wrap({required bool dark, required Widget child}) {
  return MaterialApp(
    theme: AppTheme.getTheme(0, dark),
    home: Scaffold(body: Center(child: child)),
  );
}

const _options = [
  SegmentedToggleOption(value: false, label: Text('Авто')),
  SegmentedToggleOption(value: true, label: Text('Ручной')),
];

void main() {
  testWidgets('renders both options and reports the tapped one',
      (tester) async {
    bool? tapped;
    await tester.pumpWidget(
      _wrap(
        dark: true,
        child: SegmentedToggle<bool>(
          value: false,
          options: _options,
          onChanged: (value) => tapped = value,
        ),
      ),
    );

    expect(find.text('Авто'), findsOneWidget);
    expect(find.text('Ручной'), findsOneWidget);

    await tester.tap(find.text('Ручной'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('tapping the selected option does not fire the callback',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        dark: false,
        child: SegmentedToggle<bool>(
          value: false,
          options: _options,
          onChanged: (_) => calls++,
        ),
      ),
    );

    await tester.tap(find.text('Авто'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('disabled toggle ignores taps', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        dark: true,
        child: SegmentedToggle<bool>(
          value: true,
          enabled: false,
          options: _options,
          onChanged: (_) => calls++,
        ),
      ),
    );

    await tester.tap(find.text('Авто'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });
}
