import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firmware_provider.dart';

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
    return '${seconds} с';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FirmwareProvider>();
    final isActive = provider.isBuilding || provider.isUploading;

    if (isActive && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (_activeSince == null) _activeSince = DateTime.now();
    } else if (!isActive && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _activeSince = null;
    }

    if (provider.buildLogs.isEmpty) return const SizedBox.shrink();

    final completedText = provider.lastBuildDuration != null
        ? 'готово за ${provider.lastBuildDuration!.inSeconds} с'
        : null;

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
                Text(
                  provider.isUploading
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
                  Text(
                    _elapsedText(),
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Colors.grey[600],
                    ),
                  ),
                ] else if (completedText != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    completedText,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
                const Spacer(),
                if (isActive)
                  TextButton(
                    onPressed: provider.cancelBuild,
                    child: const Text('Отмена', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          if (isActive)
            const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1),
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

                return Text(
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