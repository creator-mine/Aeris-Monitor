import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aeris/features/firmware/providers/firmware_provider.dart';
import 'package:aeris/features/firmware/widgets/firmware_source_card.dart';

void main() {
  testWidgets('shows the file/link workflow', (tester) async {
    final provider = FirmwareProvider();
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<FirmwareProvider>.value(
        value: provider,
        child: const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: [Locale('ru'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(child: FirmwareSourceCard()),
          ),
        ),
      ),
    );

    expect(find.text('Выбрать .bin'), findsOneWidget);
    expect(find.text('Ссылка на .bin или GitHub'), findsOneWidget);
    expect(find.text('Загрузить'), findsNothing);
  });
}
