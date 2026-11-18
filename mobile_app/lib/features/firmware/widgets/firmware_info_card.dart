import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/firmware_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';

class FirmwareInfoCard extends StatelessWidget {
  const FirmwareInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FirmwareProvider>(
      builder: (context, provider, child) {
        if (provider.sourcePath == null) {
          return const SizedBox.shrink();
        }

        final info = provider.projectInfo;
        final bin = provider.firmwareBinInfo;
        final latest = provider.latestVersion;

        final items = <(IconData, String, String)>[
          (Icons.memory, 'Плата', _string(info['board'], '—')),
          (
            Icons.settings_input_component,
            'Платформа',
            _string(info['platform'], '—')
          ),
          (Icons.extension, 'Фреймворк', _string(info['framework'], '—')),
          (Icons.speed, 'CPU Freq', _string(info['board_build.f_cpu'], '—')),
          (Icons.flag, 'Flash', _string(info['board_upload.flash_size'], '—')),
          (
            Icons.build_circle,
            'Уровень оптимизации',
            _string(info['build_flags'], '—')
          ),
        ];

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 8),
                    const TrText(
                      'Информация о прошивке',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TrText(
                      _string(info['envName'], ''),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...items.where((e) => e.$3 != '—').map(
                      (e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(e.$1, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            TrText(e.$2, style: const TextStyle(fontSize: 13)),
                            const Spacer(),
                            Flexible(
                              child: TrText(
                                e.$3,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (provider.gitInfo['isRepo'] == true) ...[
                  const Divider(height: 20),
                  _StatusRow(
                    icon: Icons.account_tree_outlined,
                    label: 'Ветка',
                    value: _string(provider.gitInfo['branch'], '—'),
                  ),
                  _StatusRow(
                    icon: Icons.commit,
                    label: 'Коммит',
                    value: _gitCommitLabel(provider.gitInfo),
                  ),
                  _StatusRow(
                    icon: Icons.event,
                    label: 'Коммит от',
                    value: _string(provider.gitInfo['date'], '—'),
                  ),
                ],
                const Divider(height: 24),
                _StatusRow(
                  icon: Icons.folder,
                  label: 'Бинарный файл',
                  value: bin['exists'] == true
                      ? _formatSize(bin['sizeBytes'])
                      : 'не собран',
                  status: bin['exists'] == true ? _Status.ok : _Status.error,
                ),
                _StatusRow(
                  icon: Icons.schedule,
                  label: 'Собран (bin)',
                  value: bin['exists'] == true
                      ? _formatDate(bin['modified'])
                      : '—',
                ),
                _StatusRow(
                  icon: Icons.update,
                  label: 'Актуальность',
                  value: !provider.hasUpdates
                      ? 'актуально'
                      : 'есть изменения в коде',
                  status: !provider.hasUpdates ? _Status.ok : _Status.warn,
                ),
                if (provider.hasUpdates && provider.fileChanges.isNotEmpty) ...[
                  const Divider(height: 20),
                  TrText(
                    'Изменённые файлы (${provider.fileChanges.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...provider.fileChanges.map((change) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              switch (change.kind) {
                                FileChangeKind.added =>
                                  Icons.add_circle_outline,
                                FileChangeKind.modified => Icons.edit,
                                FileChangeKind.removed =>
                                  Icons.remove_circle_outline,
                              },
                              size: 15,
                              color: _fileChangeColor(change.kind),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TrText(
                                change.path,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            TrText(
                              change.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: _fileChangeColor(change.kind),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
                if (latest != null) ...[
                  _StatusRow(
                    icon: Icons.build,
                    label: 'Последняя сборка',
                    value: 'v${latest.version} · ${latest.buildDateFormatted}',
                  ),
                  if (latest.firmwarePath != null)
                    _StatusRow(
                      icon: Icons.upload,
                      label: 'Последняя загрузка',
                      value: '${latest.lastUploadFormatted}'
                          '${latest.lastUploadPort != null ? ' → ${latest.lastUploadPort}' : ''}',
                    ),
                ],
                const Divider(height: 20),
                _JsonPreview(provider: provider),
                if (info['platformio.ini'] == 'not found' ||
                    info.containsKey('error'))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: TrText(
                      'platformio.ini не найден в выбранной папке',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _Status { ok, warn, error }

Color _fileChangeColor(FileChangeKind kind) {
  switch (kind) {
    case FileChangeKind.added:
      return Colors.green.shade700;
    case FileChangeKind.modified:
      return Colors.orange.shade800;
    case FileChangeKind.removed:
      return Colors.red.shade700;
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final _Status? status;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    switch (status) {
      case _Status.ok:
        iconColor = Colors.green;
        break;
      case _Status.warn:
        iconColor = Colors.orange;
        break;
      case _Status.error:
        iconColor = Colors.red;
        break;
      default:
        iconColor = Colors.grey[600]!;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 16, color: status == null ? Colors.grey[600] : iconColor),
          const SizedBox(width: 8),
          TrText(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Flexible(
            child: TrText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: status == null
                    ? Colors.grey[700]
                    : (status == _Status.ok
                        ? Colors.green.shade700
                        : iconColor),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _string(dynamic v, String fallback) {
  if (v == null || v.toString().trim().isEmpty) return fallback;
  return v.toString();
}

String _formatSize(dynamic bytes) {
  if (bytes == null) return '—';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(2)} МБ';
}

String _formatDate(dynamic value) {
  if (value == null) return '—';
  if (value is DateTime) {
    return DateFormat('dd.MM.yyyy HH:mm').format(value);
  }
  if (value is int) {
    return DateFormat('dd.MM.yyyy HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(value));
  }
  return value.toString();
}

String _gitCommitLabel(Map<String, dynamic> gitInfo) {
  final commit = _string(gitInfo['commit'], '—');
  final message = _string(gitInfo['message'], '').trim();
  final label = '$commit${message.isNotEmpty ? ' · $message' : ''}';
  return label.length > 40 ? '${label.substring(0, 40)}…' : label;
}

class _JsonPreview extends StatelessWidget {
  final FirmwareProvider provider;

  const _JsonPreview({required this.provider});

  @override
  Widget build(BuildContext context) {
    final info = provider.projectInfo;
    if (info.isEmpty || info.containsKey('error')) {
      return const SizedBox.shrink();
    }

    final envSection = Map<String, dynamic>.of(
      info.map((key, value) => MapEntry(key, value)),
    )
      ..remove('path')
      ..remove('envName')
      ..remove('environments')
      ..remove('error');

    if (envSection.isEmpty) return const SizedBox.shrink();

    final jsonText = const JsonEncoder.withIndent('  ').convert(envSection);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.code, size: 18),
        title: const TrText(
          'Параметры среды (platformio.ini)',
          style: TextStyle(fontSize: 13),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 220),
                width: 420,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  child: SelectableText(
                    jsonText,
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
    );
  }
}
