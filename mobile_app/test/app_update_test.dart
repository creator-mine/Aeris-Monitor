import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aeris/core/api/app_update_service.dart';
import 'package:aeris/core/config/app_config.dart';
import 'package:aeris/features/settings/providers/update_provider.dart';

import 'support/update_fakes.dart';

class _FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _githubJson({
  String tag = 'v9.9.9',
  String body = 'Release notes',
}) =>
    {
      'tag_name': tag,
      'name': 'Aeris Monitor $tag',
      'html_url': 'https://github.com/creator-mine/Aeris-App/releases/tag/$tag',
      'body': body,
      'published_at': '2026-11-20T17:39:56Z',
      'assets': [
        {
          'name': 'aeris_setup_9.9.9.exe',
          'browser_download_url': 'https://example.com/aeris_setup_9.9.9.exe',
        },
        {
          'name': 'aeris-monitor-9.9.9.apk',
          'browser_download_url': 'https://example.com/aeris-monitor-9.9.9.apk',
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppRelease', () {
    test('parses version, notes and assets from the GitHub payload', () {
      final release = AppRelease.fromGitHubJson(_githubJson());

      expect(release, isNotNull);
      expect(release!.version, '9.9.9');
      expect(release.tag, 'v9.9.9');
      expect(release.notes, 'Release notes');
      expect(release.assets, hasLength(2));
      expect(release.publishedAt, isNotNull);
      expect(
        release.installerUrl(android: false),
        'https://example.com/aeris_setup_9.9.9.exe',
      );
      expect(
        release.installerUrl(android: true),
        'https://example.com/aeris-monitor-9.9.9.apk',
      );
    });

    test('installer is null when the release has no build for a platform', () {
      final release = AppRelease.fromGitHubJson({
        'tag_name': 'v1.3.5',
        'html_url': 'https://example.com/release',
        'assets': const [],
      });

      expect(release, isNotNull);
      expect(release!.installerUrl(android: false), isNull);
      expect(release.installerUrl(android: true), isNull);
    });

    test('rejects a payload without a version', () {
      expect(
        AppRelease.fromGitHubJson({
          'tag_name': 'nightly',
          'name': 'Nightly',
          'html_url': 'https://example.com/release',
        }),
        isNull,
      );
    });
  });

  group('AppUpdateService', () {
    test('reads /releases/latest and compares against the app version',
        () async {
      final dio = Dio();
      RequestOptions? seen;
      dio.httpClientAdapter = _FakeAdapter((options) async {
        seen = options;
        return ResponseBody.fromString(
          jsonEncode(_githubJson()),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final service = AppUpdateService(dio: dio);
      final release = await service.latestRelease();

      expect(
        seen?.uri.toString(),
        'https://api.github.com/repos/creator-mine/Aeris-App/releases/latest',
      );
      expect(release.version, '9.9.9');
      expect(service.isNewer(release), isTrue);
      expect(service.isNewer(fakeRelease(AppConfig.appVersion)), isFalse);
    });

    test('maps 403 to a rate-limit message', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => ResponseBody.fromString('{}', 403),
      );

      final service = AppUpdateService(dio: dio);
      await expectLater(
        service.latestRelease(),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('ограничил'),
          ),
        ),
      );
    });

    test('maps 404 to a "no releases" message', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => ResponseBody.fromString('{}', 404),
      );

      final service = AppUpdateService(dio: dio);
      await expectLater(
        service.latestRelease(),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('нет релизов'),
          ),
        ),
      );
    });
  });

  group('UpdateProvider', () {
    test('enables automatic checks by default and persists the toggle',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = UpdateProvider(service: FakeUpdateService());
      await provider.init();

      expect(provider.autoCheck, isTrue);
      expect(provider.autoCheckDue, isTrue);
      expect(provider.state, UpdateCheckState.idle);

      await provider.setAutoCheck(false);
      expect(provider.autoCheckDue, isFalse);

      final reloaded = UpdateProvider(service: FakeUpdateService());
      await reloaded.init();
      expect(reloaded.autoCheck, isFalse);
      expect(reloaded.autoCheckDue, isFalse);
    });

    test('manual check exposes a newer release and stores the check time',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = FakeUpdateService(release: fakeRelease('1.3.5'));
      final provider = UpdateProvider(service: service);
      await provider.init();

      await provider.checkNow();

      expect(service.calls, 1);
      expect(provider.state, UpdateCheckState.updateAvailable);
      expect(provider.availableVersion, '1.3.5');
      expect(provider.error, isNull);
      expect(provider.lastCheckAt, isNotNull);
      expect(provider.autoCheckDue, isFalse);

      // The 4-hour interval is now running: no extra GitHub calls.
      await provider.maybeAutoCheck();
      expect(service.calls, 1);

      final reloaded = UpdateProvider(service: service);
      await reloaded.init();
      expect(reloaded.autoCheckDue, isFalse);
    });

    test('reports up to date when the published version matches', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = UpdateProvider(
        service: FakeUpdateService(release: fakeRelease('1.3.4'), newer: false),
      );
      await provider.init();

      await provider.checkNow();

      expect(provider.state, UpdateCheckState.upToDate);
      expect(provider.available, isNull);
    });

    test('keeps the error message and does not throw', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = UpdateProvider(
        service: FakeUpdateService(
          error: const AppUpdateException('Нет связи с GitHub: timeout'),
        ),
      );
      await provider.init();

      await provider.checkNow();

      expect(provider.state, UpdateCheckState.failed);
      expect(provider.error, contains('timeout'));
      expect(provider.lastCheckAt, isNotNull);
    });

    test('does nothing before init or with automatic checks off', () async {
      SharedPreferences.setMockInitialValues({'auto_check_updates': false});
      final service = FakeUpdateService(release: fakeRelease('1.3.5'));

      final notInitialized = UpdateProvider(service: service);
      await notInitialized.maybeAutoCheck();
      expect(service.calls, 0);

      final provider = UpdateProvider(service: service);
      await provider.init();
      await provider.maybeAutoCheck();
      expect(service.calls, 0);
    });
  });
}
