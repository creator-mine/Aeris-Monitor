import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../models/firmware_version.dart';
import '../../../shared/utils/line_diff.dart';
import '../providers/firmware_provider.dart';

class VersionHistory extends StatelessWidget {
  const VersionHistory({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FirmwareProvider>(
      builder: (context, provider, child) {
        final versions = provider.versionsForDevice;

        return Card(
          margin: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.history, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'История сборок (${versions.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (versions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Нет сохранённых сборок',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ...versions.map((v) => _VersionTile(
                      version: v,
                      onTap: () => _showDetails(context, provider, v),
                      onUpload: () => provider.uploadVersion(v),
                      onExport: () => _export(context, v),
                      onDelete: () => _confirmDelete(context, provider, v),
                    )),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, FirmwareProvider provider, FirmwareVersion version) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сборку?'),
        content: Text('Версия ${version.version} будет удалена навсегда.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteVersion(version.id);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context, FirmwareProvider provider, FirmwareVersion version) {
    final previous = provider.previousVersionOf(version);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Прошивка v${version.version}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetaRow('Устройство', version.deviceLabel),
                      _MetaRow('Собрано', version.buildDateFormatted),
                      _MetaRow('Загружено', version.lastUploadFormatted),
                      if (version.lastUploadPort != null)
                        _MetaRow('Порт загрузки', version.lastUploadPort!),
                      if (version.buildHash != null)
                        _MetaRow(version.isBuilt ? 'Хэш исходников' : 'SHA-256', version.buildHash!.substring(0, min(12, version.buildHash!.length)), monospace: true),
                      _MetaRow('Источник', version.sourcePath, monospace: true),
                      if (version.firmwarePath != null)
                        _MetaRow('firmware.bin', version.firmwarePath!, monospace: true),
                      if (previous != null) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Text(
                          'Изменения конфига (v${previous.version} → v${version.version})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _ConfigDiff(previous: previous, current: version),
                      ],
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      const Text(
                        'Конфиг на момент сборки',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _ConfigSnapshotView(version: version),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, FirmwareVersion version) async {
    final messenger = ScaffoldMessenger.of(context);
    if (kIsWeb) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Экспорт прошивки доступен только в настольной версии'),
      ));
      return;
    }
    final path = version.firmwarePath;
    if (path == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Путь к прошивке не сохранён')));
      return;
    }

    final binFile = File(path);
    if (!await binFile.exists()) {
      messenger.showSnackBar(const SnackBar(content: Text('Файл firmware.bin не найден')));
      return;
    }

    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Куда экспортировать прошивку?',
    );
    if (dir == null) return;

    final baseName = 'firmware_v${version.version}_${version.pioEnvironment}';
    final binTarget = p.join(dir, '$baseName.bin');

    try {
      await binFile.copy(binTarget);

      final manifest = {
        'version': version.version,
        'deviceType': version.deviceType,
        'deviceLabel': version.deviceLabel,
        'buildDate': version.buildDate.toIso8601String(),
        'buildHash': version.buildHash,
        'sourcePath': version.sourcePath,
        'firmwarePath': version.firmwarePath,
        'lastUploadPort': version.lastUploadPort,
        'lastUploadDate': version.lastUploadDate?.toIso8601String(),
        'fileHashes': version.fileHashes,
        'configSnapshot': version.configSnapshot,
      };

      final manifestTarget = p.join(dir, '${baseName}_manifest.json');
      await File(manifestTarget).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );

      messenger.showSnackBar(SnackBar(content: Text('Экспортировано: $binTarget')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
    }
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const _MetaRow(this.label, this.value, {this.monospace = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigSnapshotView extends StatelessWidget {
  final FirmwareVersion version;

  const _ConfigSnapshotView({required this.version});

  @override
  Widget build(BuildContext context) {
    final snapshot = version.configSnapshot;
    final files = snapshot?['files'];
    if (files == null || (files as Map).isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Конфиг не сохранён для этой версии',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    return Column(
      children: files.entries.map((entry) {
        final name = entry.key.toString();
        final content = entry.value.toString();
        return _FileExpansionTile(name: name, content: content);
      }).toList(),
    );
  }
}

class _ConfigDiff extends StatelessWidget {
  final FirmwareVersion previous;
  final FirmwareVersion current;

  const _ConfigDiff({required this.previous, required this.current});

  @override
  Widget build(BuildContext context) {
    final prevFiles = (previous.configSnapshot?['files'] as Map?) ?? const <dynamic, dynamic>{};
    final currFiles = (current.configSnapshot?['files'] as Map?) ?? const <dynamic, dynamic>{};

    if (prevFiles.isEmpty || currFiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Для одной из версий нет конфига',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    final names = <String>{
      ...prevFiles.keys.map((e) => e.toString()),
      ...currFiles.keys.map((e) => e.toString()),
    };

    return Column(
      children: names.map((name) {
        final oldContent = prevFiles[name]?.toString() ?? '';
        final newContent = currFiles[name]?.toString() ?? '';
        final lines = diffLines(
          const LineSplitter().convert(oldContent),
          const LineSplitter().convert(newContent),
        );
        final changed = lines.any((l) => l.prefix != ' ');
        return _FileExpansionTile(
          name: name,
          isDiff: true,
          diffLines: lines,
          badge: changed ? null : 'без изменений',
        );
      }).toList(),
    );
  }
}

class _FileExpansionTile extends StatelessWidget {
  final String name;
  final String? content;
  final List<DiffLine>? diffLines;
  final String? badge;
  final bool isDiff;

  const _FileExpansionTile({
    required this.name,
    this.content,
    this.diffLines,
    this.badge,
    this.isDiff = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(Icons.description_outlined, size: 18, color: Colors.grey[600]),
          title: Row(
            children: [
              Flexible(
                child: Text(name, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Text(
                  badge!,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ],
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  width: isDiff ? 460 : 440,
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: isDiff ? Colors.grey.shade100 : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    child: isDiff
                        ? _buildDiff()
                        : SelectableText(
                            content ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiff() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: diffLines!.map((line) {
        final color = switch (line.prefix) {
          '+' => Colors.green.shade700,
          '-' => Colors.red.shade700,
          _ => Colors.grey.shade700,
        };
        return Text(
          '${line.prefix} ${line.text}',
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: color,
            backgroundColor: line.prefix == '+'
                ? Colors.green.withValues(alpha: 0.08)
                : line.prefix == '-'
                    ? Colors.red.withValues(alpha: 0.08)
                    : null,
          ),
        );
      }).toList(),
    );
  }
}

class _VersionTile extends StatelessWidget {
  final FirmwareVersion version;
  final VoidCallback onTap;
  final VoidCallback onUpload;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _VersionTile({
    required this.version,
    required this.onTap,
    required this.onUpload,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: version.isBuilt ? Colors.green.shade50 : Colors.grey.shade100,
        child: Icon(
          Icons.code,
          color: version.isBuilt ? Colors.green : Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        'v${version.version}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            'Собрано: ${version.buildDateFormatted}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            'Загружено: ${version.lastUploadFormatted}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (version.firmwarePath != null)
            Text(
              'firmware.bin готов (${_binExists(version) ? 'на месте' : 'не найден'})',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          if (version.buildHash != null)
            Text(
              'Hash: ${version.buildHash!.substring(0, min(8, version.buildHash!.length))}...',
              style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'upload':
              onUpload();
              break;
            case 'export':
              onExport();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'upload',
            child: ListTile(
              leading: Icon(Icons.upload, size: 20),
              title: Text('Загрузить'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'export',
            child: ListTile(
              leading: Icon(Icons.save_alt, size: 20),
              title: Text('Экспорт'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete, size: 20, color: Colors.red),
              title: Text('Удалить', style: TextStyle(color: Colors.red)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  bool _binExists(FirmwareVersion version) {
    if (kIsWeb) return false;
    final path = version.firmwarePath;
    if (path == null) return false;
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }
}