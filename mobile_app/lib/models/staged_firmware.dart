import 'dart:io';

import 'package:path/path.dart' as p;

/// A firmware image picked from disk or downloaded from a URL and waiting to
/// be flashed to the board. Unlike [FirmwareVersion] this is not persisted:
/// the image becomes a history entry only after a successful flash.
class StagedFirmware {
  final String path;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String? version;
  final String deviceType;
  final String? sourceUrl;
  final bool downloaded;

  const StagedFirmware({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.deviceType,
    this.version,
    this.sourceUrl,
    this.downloaded = false,
  });

  String get deviceLabel => switch (deviceType) {
        'esp32' => 'ESP32',
        'esp32-c3' => 'ESP32-C3',
        'esp32-c6' => 'ESP32-C6',
        'esp32-s3' => 'ESP32-S3',
        _ => deviceType.toUpperCase(),
      };

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes Б';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} КБ';
    return '${(kb / 1024).toStringAsFixed(2)} МБ';
  }

  String get shortHash =>
      sha256.length <= 16 ? sha256 : '${sha256.substring(0, 16)}…';

  String get originLabel {
    final url = sourceUrl;
    if (url != null && url.isNotEmpty) return url;
    return p.dirname(path);
  }

  /// Deletes the staged copy. The caller is responsible for not deleting a file
  /// that has already been recorded in the firmware history.
  Future<void> deleteFile() async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A locked/temporarily unavailable file is not worth failing the UI over.
    }
  }
}
