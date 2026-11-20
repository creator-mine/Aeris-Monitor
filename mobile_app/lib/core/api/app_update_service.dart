import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../utils/firmware_file.dart';
import '../utils/version.dart';

class AppUpdateException implements Exception {
  final String message;
  const AppUpdateException(this.message);

  @override
  String toString() => message;
}

/// A published application build from the GitHub Releases API.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.htmlUrl,
    this.notes = '',
    this.publishedAt,
    this.assets = const {},
  });

  /// Numeric version without the tag prefix, e.g. `1.3.4`.
  final String version;

  /// Release tag as published, e.g. `v1.3.4`.
  final String tag;

  /// Release page on GitHub.
  final String htmlUrl;

  /// Release notes (markdown body).
  final String notes;

  final DateTime? publishedAt;

  /// Asset file name -> browser download URL.
  final Map<String, String> assets;

  /// Direct installer link (`.apk` on Android, `.exe` on desktop), or null
  /// when the release has no build for that platform.
  String? installerUrl({required bool android}) {
    final suffix = android ? '.apk' : '.exe';
    for (final entry in assets.entries) {
      if (entry.key.toLowerCase().endsWith(suffix)) return entry.value;
    }
    return null;
  }

  static AppRelease? fromGitHubJson(Map<dynamic, dynamic> data) {
    final tag = data['tag_name']?.toString() ?? '';
    final name = data['name']?.toString() ?? '';
    final version = firmwareVersionFromName(tag) ??
        firmwareVersionFromName(name) ??
        firmwareVersionFromName((data['html_url']?.toString() ?? ''));
    if (version == null) return null;

    final htmlUrl = data['html_url']?.toString() ?? '';
    if (htmlUrl.isEmpty) return null;

    final assets = <String, String>{};
    final rawAssets = data['assets'];
    if (rawAssets is List) {
      for (final asset in rawAssets) {
        if (asset is! Map) continue;
        final assetName = asset['name']?.toString();
        final url = asset['browser_download_url']?.toString();
        if (assetName != null && assetName.isNotEmpty && url != null) {
          assets[assetName] = url;
        }
      }
    }

    DateTime? publishedAt;
    final published = data['published_at']?.toString();
    if (published != null && published.isNotEmpty) {
      publishedAt = DateTime.tryParse(published);
    }

    return AppRelease(
      version: version,
      tag: tag.isEmpty ? 'v$version' : tag,
      htmlUrl: htmlUrl,
      notes: data['body']?.toString() ?? '',
      publishedAt: publishedAt,
      assets: assets,
    );
  }
}

/// Reads the current app release from GitHub Releases.
///
/// The API is public and unauthenticated; a check every few hours stays well
/// inside GitHub's 60 requests/hour limit.
class AppUpdateService {
  AppUpdateService({Dio? dio, this.repository = defaultRepository})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: AppConfig.connectionTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              followRedirects: true,
            ));

  static const String defaultRepository = 'creator-mine/Aeris-App';

  final Dio _dio;
  final String repository;

  /// True when [release] is newer than the version baked into this build.
  bool isNewer(AppRelease release) =>
      isVersionNewer(release.version, AppConfig.appVersion);

  Future<AppRelease> latestRelease() async {
    final Response<dynamic> response;
    try {
      response = await _dio.getUri<dynamic>(
        Uri.https('api.github.com', '/repos/$repository/releases/latest'),
        options: Options(
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'Aeris-Monitor-App',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (e) {
      throw AppUpdateException(
        'Нет связи с GitHub: ${e.message ?? e.type.name}',
      );
    }

    if (response.statusCode == 404) {
      throw const AppUpdateException('У репозитория ещё нет релизов');
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const AppUpdateException(
        'GitHub временно ограничил запросы. Попробуйте позже.',
      );
    }
    if (response.statusCode != 200) {
      throw AppUpdateException(
        'GitHub API вернул ${response.statusCode}',
      );
    }

    dynamic data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        data = null;
      }
    }
    if (data is! Map) {
      throw const AppUpdateException('Не удалось разобрать ответ GitHub');
    }

    final release = AppRelease.fromGitHubJson(data);
    if (release == null) {
      throw const AppUpdateException('В релизе не указана версия');
    }
    return release;
  }
}
