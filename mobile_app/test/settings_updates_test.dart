import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aeris/core/config/app_config.dart';
import 'package:aeris/core/i18n/l10n.dart';
import 'package:aeris/features/settings/providers/update_provider.dart';
import 'package:aeris/features/settings/widgets/updates_section.dart';
import 'package:aeris/shared/theme/app_theme.dart';

import 'support/update_fakes.dart';

Future<void> _pumpSection(
  WidgetTester tester,
  UpdateProvider provider,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.getTheme(0, false),
        locale: const Locale('ru'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: UpdatesSection(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('updates card matches the settings layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = UpdateProvider(
      service: FakeUpdateService(release: fakeRelease('9.9.9')),
    );
    await provider.init();

    await _pumpSection(tester, provider);

    expect(find.text('Обновления'), findsOneWidget);
    expect(find.text('Проверять обновления'), findsOneWidget);
    expect(
      find.text('Автоматически раз в несколько часов через GitHub Releases'),
      findsOneWidget,
    );
    expect(find.text('Проверить обновления'), findsOneWidget);
    expect(find.text('Проверить наличие новой версии'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('toggle turns automatic checks off and persists it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = UpdateProvider(
      service: FakeUpdateService(release: fakeRelease('9.9.9')),
    );
    await provider.init();
    await _pumpSection(tester, provider);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(provider.autoCheck, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(UpdateProvider.autoCheckKey), isFalse);
  });

  testWidgets('manual check shows the available release dialog',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = UpdateProvider(
      service: FakeUpdateService(release: fakeRelease('9.9.9')),
    );
    await provider.init();
    await _pumpSection(tester, provider);

    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();

    expect(provider.state, UpdateCheckState.updateAvailable);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Доступна версия 9.9.9'), findsWidgets);
    expect(
      find.text('Установлено: ${AppConfig.appVersion}'),
      findsOneWidget,
    );
    expect(find.text('Новое: 9.9.9'), findsOneWidget);
    expect(find.text('Позже'), findsOneWidget);
    expect(find.text('Открыть релиз'), findsOneWidget);
    expect(find.text('Скачать'), findsOneWidget);
  });

  testWidgets('manual check reports the latest version', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = UpdateProvider(
      service: FakeUpdateService(
        release: fakeRelease(AppConfig.appVersion),
        newer: false,
      ),
    );
    await provider.init();
    await _pumpSection(tester, provider);

    await tester.tap(find.text('Проверить обновления'));
    await tester.pumpAndSettle();

    expect(provider.state, UpdateCheckState.upToDate);
    expect(find.text('Установлена последняя версия'), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
