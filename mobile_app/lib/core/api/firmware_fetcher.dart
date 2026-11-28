import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/staged_firmware.dart';
import '../config/app_config.dart';
import '../utils/firmware_file.dart';
import '../utils/firmware_link.dart';

class FirmwareFetchException implements Exception {
  final String message;
  const FirmwareFetchException(this.message);

  @override
  String toString() => message;
}

class _DownloadTarget {
  final Uri url;
  final String fileName;
  final String? version;
  final int? sizeBytes;

  const _DownloadTarget({
    required this.url,
    required this.fileName,
    this.version,
    this.sizeBytes,
  });
}

/// Stages a firmware image for flashing: copies a local `.bin` or downloads one
/// from GitHub / the published OTA host. The staged file always lives in the
/// app's support directory so history entries keep working after a restart.
class FirmwareFetcher {
  static const int maxFirmwareBytes = 16 * 1024 * 1024;
  static const Duration _downloadTimeout = Duration(minutes: 3);

  final Dio _dio;
  final Directory? _storageDir;

  FirmwareFetcher({Dio? dio, Directory? storageDir})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: AppConfig.connectionTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              followRedirects: true,
            )),
        _storageDir = storageDir;

  Future<StagedFirmware> stageLocalFile(
    String sourcePath, {
    required String preferredDeviceType,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FirmwareFetchException('Файл не найден');
    }
    final sourceBytes = await source.length();
    _checkSize(sourceBytes);

    final dir = await _firmwareDir();
    final fileName = safeFirmwareFileName(p.basename(sourcePath));
    final target = File(
      p.join(
        dir.path,
        '${DateTime.now().millisecondsSinceEpoch}_$fileName',
      ),
    );
    await source.copy(target.path);

    try {
      final sha = await _validateImage(target, expectedBytes: sourceBytes);
      return StagedFirmware(
        path: target.path,
        fileName: fileName,
        sizeBytes: sourceBytes,
        sha256: sha,
        version: firmwareVersionFromName(fileName),
        deviceType: firmwareDeviceTypeFromName(fileName) ?? preferredDeviceType,
        sourceUrl: null,
        downloaded: false,
      );
    } catch (_) {
      await _delete(target);
      rethrow;
    }
  }

  Future<StagedFirmware> downloadFromUrl(
    String input, {
    required String preferredDeviceType,
    String? version,
    String? expectedSha256,
    int? expectedBytes,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final link = FirmwareLink.parse(input);
    if (link == null) {
      throw const FirmwareFetchException(
        'Нужна ссылка https://... на файл .bin, GitHub-файл или релиз',
      );
    }

    late final _DownloadTarget target;
    try {
      target = await _resolve(link, preferredDeviceType);
    } on FirmwareFetchException {
      rethrow;
    } on DioException catch (e) {
      throw FirmwareFetchException(
        'Не удалось обратиться к GitHub: ${e.message ?? e.type.name}',
      );
    }
    final dir = await _firmwareDir();
    final fileName = safeFirmwareFileName(target.fileName);
    final finalFile = File(
      p.join(
        dir.path,
        '${DateTime.now().millisecondsSinceEpoch}_$fileName',
      ),
    );
    final partFile = File('${finalFile.path}.part');

    try {
      final response = await _dio.downloadUri(
        target.url,
        partFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          followRedirects: true,
          receiveTimeout: _downloadTimeout,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      );

      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
              '';
      if (contentType.contains('text/html') ||
          contentType.contains('application/json')) {
        throw const FirmwareFetchException(
          'По ссылке пришла веб-страница, а не файл прошивки. '
          'Откройте файл .bin или используйте ссылку на релиз GitHub.',
        );
      }

      if (await partFile.exists()) {
        await partFile.rename(finalFile.path);
      } else {
        throw const FirmwareFetchException('Скачивание не создало файл');
      }

      final expectedSize = expectedBytes ?? target.sizeBytes;
      final sha = await _validateImage(
        finalFile,
        expectedSha256: expectedSha256,
        expectedBytes: expectedSize,
      );

      return StagedFirmware(
        path: finalFile.path,
        fileName: fileName,
        sizeBytes: await finalFile.length(),
        sha256: sha,
        version: version ?? target.version ?? firmwareVersionFromName(fileName),
        deviceType: firmwareDeviceTypeFromName(fileName) ?? preferredDeviceType,
        sourceUrl: target.url.toString(),
        downloaded: true,
      );
    } catch (e) {
      await _delete(partFile);
      await _delete(finalFile);
      if (e is DioException && CancelToken.isCancel(e)) {
        throw const FirmwareFetchException('Скачивание отменено');
      }
      if (e is FirmwareFetchException) rethrow;
      if (e is DioException) {
        final status = e.response?.statusCode;
        throw FirmwareFetchException(
          status == 404
              ? 'Файл или релиз не найден (404)'
              : 'Не удалось скачать прошивку: ${e.message ?? e.type.name}',
        );
      }
      throw FirmwareFetchException('Не удалось скачать прошивку: $e');
    }
  }

  Future<_DownloadTarget> _resolve(
    FirmwareLink link,
    String preferredDeviceType,
  ) async {
    if (!link.isGithubRelease) {
      final uri = link.directUri!;
      final name = uri.pathSegments.isEmpty
          ? 'firmware.bin'
          : p.basename(uri.pathSegments.last);
      if (!name.toLowerCase().endsWith('.bin')) {
        throw const FirmwareFetchException('Ссылка должна указывать на .bin');
      }
      return _DownloadTarget(url: uri, fileName: name);
    }

    final owner = link.owner!;
    final repo = link.repo!;
    final tag = link.tag;
    final apiPath = tag == null
        ? '/repos/$owner/$repo/releases/latest'
        : '/repos/$owner/$repo/releases/tags/${Uri.encodeComponent(tag)}';

    final response = await _dio.getUri(
      Uri.https('api.github.com', apiPath),
      options: Options(
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'Aeris-Monitor-App',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode == 404) {
      throw FirmwareFetchException(
        tag == null
            ? 'У репозитория $owner/$repo нет релизов'
            : 'Релиз $tag не найден в $owner/$repo',
      );
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const FirmwareFetchException(
        'GitHub временно ограничил запросы. Попробуйте позже или вставьте '
        'прямую ссылку на файл .bin.',
      );
    }
    if (response.statusCode != 200) {
      throw FirmwareFetchException(
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
      throw const FirmwareFetchException('Не удалось разобрать ответ GitHub');
    }

    final assets = (data['assets'] as List?) ?? const [];
    final bins = <Map>[];
    for (final asset in assets) {
      if (asset is Map) {
        final name = asset['name']?.toString().toLowerCase() ?? '';
        if (name.endsWith('.bin')) bins.add(asset);
      }
    }
    if (bins.isEmpty) {
      throw const FirmwareFetchException(
        'В релизе GitHub нет файлов .bin',
      );
    }

    final wanted = _tokensFor(preferredDeviceType);
    Map? chosen;
    for (final asset in bins) {
      final name = asset['name']?.toString().toLowerCase() ?? '';
      if (wanted.any(name.contains)) {
        chosen = asset;
        break;
      }
    }
    // A release with one generic main.bin is fine for the legacy C3 layout.
    if (chosen == null && bins.length == 1) chosen = bins.first;

    if (chosen == null) {
      final names = bins
          .map((a) => a['name']?.toString() ?? '?')
          .where((n) => n.isNotEmpty)
          .join(', ');
      throw FirmwareFetchException(
        'В релизе нет прошивки для $preferredDeviceType. Доступно: $names',
      );
    }

    final name = chosen['name']?.toString() ?? 'firmware.bin';
    final url = chosen['browser_download_url']?.toString();
    if (url == null || url.isEmpty) {
      throw const FirmwareFetchException(
        'У файла релиза нет ссылки для скачивания',
      );
    }

    final tagName = data['tag_name']?.toString();
    final version = tagName == null
        ? firmwareVersionFromName(name)
        : firmwareVersionFromName(tagName) ?? firmwareVersionFromName(name);

    return _DownloadTarget(
      url: Uri.parse(url),
      fileName: name,
      version: version,
      sizeBytes: _intOrNull(chosen['size']),
    );
  }

  List<String> _tokensFor(String deviceType) {
    switch (deviceType) {
      case 'esp32-s3':
        return const ['esp32s3', 'esp32-s3', 's3'];
      case 'esp32-c6':
        return const ['esp32c6', 'esp32-c6', 'c6'];
      case 'esp32':
        // Exact classic-ESP32 markers; a bare "esp32" token would also match
        // esp32c3/c6/s3 asset names.
        return const [
          'esp32-classic',
          'esp32classic',
          'esp32dev',
          '-esp32.',
          '_esp32.',
        ];
      default:
        return const ['esp32c3', 'esp32-c3', 'c3', 'main.bin'];
    }
  }

  int? _intOrNull(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<Directory> _firmwareDir() async {
    final base = _storageDir ?? await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'firmware'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  void _checkSize(int bytes) {
    if (bytes <= 0) {
      throw const FirmwareFetchException('Файл прошивки пустой');
    }
    if (bytes > maxFirmwareBytes) {
      throw const FirmwareFetchException(
        'Файл больше 16 МБ — похоже, это не образ приложения ESP32',
      );
    }
  }

  Future<String> _validateImage(
    File file, {
    String? expectedSha256,
    int? expectedBytes,
  }) async {
    final bytes = await file.readAsBytes();
    _checkSize(bytes.length);
    if (expectedBytes != null &&
        expectedBytes > 0 &&
        bytes.length != expectedBytes) {
      throw FirmwareFetchException(
        'Размер не совпал: ожидалось $expectedBytes Б, получено ${bytes.length} Б',
      );
    }
    if (bytes.isEmpty || bytes.first != 0xE9) {
      throw const FirmwareFetchException(
        'Это не образ ESP32: файл должен начинаться с байта 0xE9',
      );
    }
    final sha = sha256.convert(bytes).toString();
    if (expectedSha256 != null &&
        expectedSha256.isNotEmpty &&
        sha.toLowerCase() != expectedSha256.toLowerCase()) {
      throw const FirmwareFetchException(
        'SHA-256 не совпал с манифестом — файл повреждён или подменён',
      );
    }
    return sha;
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup; the original error is more useful to the user.
    }
  }
}
