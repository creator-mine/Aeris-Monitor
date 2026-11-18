import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/firmware_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

class BuildLogWidget extends StatefulWidget {
  const BuildLogWidget({super.key});

  @override
  State<BuildLogWidget> createState() => _BuildLogWidgetState();
}

class _BuildLogWidgetState extends State<BuildLogWidget> {
  Timer? _timer;
  DateTime? _activeSince;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _elapsedText() {
    if (_activeSince == null) return '';
    final elapsed = DateTime.now().difference(_activeSince!);
    final seconds = elapsed.inSeconds;
    return '$seconds с';
  }

  /// Returns the `sudo apt install ...` command suggested in the log, if any.
  String? _extractAptCommand(List<String> logs) {
    for (final line in logs.reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('sudo apt install')) return trimmed;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FirmwareProvider>();
    final isActive = provider.isBuilding ||
        provider.isUploading ||
        provider.isStaging ||
        provider.isInstallingPlatformio;

    if (isActive && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      _activeSince ??= DateTime.now();
    } else if (!isActive && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _activeSince = null;
    }

    if (provider.buildLogs.isEmpty) return const SizedBox.shrink();

    final completedText = provider.lastBuildDuration != null
        ? 'готово за ${provider.lastBuildDuration!.inSeconds} с'
        : null;
    final aptCommand = _extractAptCommand(provider.buildLogs);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.settings : Icons.terminal,
                  size: 20,
                  color: isActive ? Colors.orange : Colors.blue,
                ),
                const SizedBox(width: 8),
                TrText(
                  provider.isInstallingPlatformio
                      ? 'Установка PlatformIO...'
                      : provider.isUploading
                          ? 'Загрузка...'
                          : isActive
                              ? 'Сборка...'
                              : 'Лог сборки',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 12),
                  TrText(
                    _elapsedText(),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Colors.grey[600],
                    ),
                  ),
                ] else if (completedText != null) ...[
                  const SizedBox(width: 12),
                  TrText(
                    completedText,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: L10n.of(context, 'Скопировать лог'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () async {
                    final text = provider.buildLogs.join('\n');
                    if (text.isEmpty) return;
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: TrText('Лог скопирован в буфер обмена'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                if (isActive)
                  TextButton(
                    onPressed: provider.cancelBuild,
                    child: const TrText('Отмена',
                        style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          if (isActive) const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1),
          if (aptCommand != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      aptCommand,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: L10n.of(context, 'Скопировать команду'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: aptCommand));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: TrText('Команда скопирована в буфер обмена'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          Container(
            height: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]
                  : Colors.grey[100],
            ),
            child: ListView.builder(
              itemCount: provider.buildLogs.length,
              itemBuilder: (context, index) {
                final line = provider.buildLogs[index];
                Color? lineColor;

                if (line.contains('[SUCCESS]')) {
                  lineColor = Colors.green;
                } else if (line.contains('[ERROR]')) {
                  lineColor = Colors.red;
                } else if (line.contains('[CANCELLED]')) {
                  lineColor = Colors.orange;
                } else if (line.contains('[STDERR]')) {
                  lineColor = Colors.red.shade300;
                }

                return TrText(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: lineColor,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
