import 'package:dio/dio.dart';
import 'package:aeris/core/api/app_update_service.dart';

/// Service stub: no network, deterministic newer/older answer.
class FakeUpdateService extends AppUpdateService {
  FakeUpdateService({
    this.release,
    this.error,
    this.newer = true,
  }) : super(dio: Dio());

  final AppRelease? release;
  final AppUpdateException? error;
  final bool newer;
  int calls = 0;

  @override
  Future<AppRelease> latestRelease() async {
    calls++;
    if (error != null) throw error!;
    return release!;
  }

  @override
  bool isNewer(AppRelease release) => newer;
}

AppRelease fakeRelease(String version) => AppRelease(
      version: version,
      tag: 'v$version',
      htmlUrl:
          'https://github.com/creator-mine/Aeris-App/releases/tag/v$version',
      notes: '## Changes\n- Wi-Fi improvements',
      assets: {
        'aeris_setup_$version.exe':
            'https://github.com/creator-mine/Aeris-App/releases/download/v$version/aeris_setup_$version.exe',
        'aeris-monitor-$version.apk':
            'https://github.com/creator-mine/Aeris-App/releases/download/v$version/aeris-monitor-$version.apk',
      },
    );
