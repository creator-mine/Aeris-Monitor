import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves [content] as a UTF-8 CSV file.
///
/// - Android/iOS: writes to the temporary directory and opens the system
///   share sheet, so the user can save it anywhere.
/// - Desktop: native folder picker.
/// - Web: unsupported (returns null).
Future<String?> exportCsv(String suggestedName, String content) async {
  if (kIsWeb) return null;

  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$suggestedName');
    await file.writeAsBytes(utf8.encode(content));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: suggestedName),
    );
    return file.path;
  }

  final dir = await FilePicker.getDirectoryPath(
    dialogTitle: 'Куда сохранить $suggestedName?',
  );
  if (dir == null) return null;

  final target = '$dir${Platform.pathSeparator}$suggestedName';
  try {
    await File(target).writeAsBytes(utf8.encode(content));
    return target;
  } catch (_) {
    rethrow;
  }
}
