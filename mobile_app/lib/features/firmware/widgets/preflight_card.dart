import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/firmware_provider.dart';

const _platformioDocs = 'https://docs.platformio.org';

class PreflightCard extends StatelessWidget {
  const PreflightCard({super.key});

  Future<void> _openDocs(BuildContext context) async {
    final uri = Uri.parse(_platformioDocs);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть документацию')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть документацию: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FirmwareProvider>(
      builder: (context, provider, child) {
        final items = provider.preflightItems;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Проверки перед сборкой',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Документация PlatformIO',
                      onPressed: () => _openDocs(context),
                      icon: const Icon(Icons.menu_book_outlined, size: 20),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          provider.isPreflightChecking || provider.sourcePath == null
                              ? null
                              : provider.runPreflight,
                      icon: provider.isPreflightChecking
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_add_check, size: 18),
                      label: Text(provider.isPreflightChecking ? 'Проверка...' : 'Запустить'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (provider.isPreflightChecking)
                  const LinearProgressIndicator(minHeight: 2),
                if (items.isEmpty && !provider.isPreflightChecking)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Запустите проверку, чтобы убедиться в готовности окружения к сборке.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  )
                else
                  ...items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item.ok ? Icons.check_circle : Icons.cancel,
                              size: 17,
                              color: item.ok ? Colors.green.shade600 : Colors.red.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.title,
                              style: const TextStyle(fontSize: 13),
                            ),
                            const Spacer(),
                            Flexible(
                              child: Text(
                                item.detail,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _openDocs(context),
                  child: Row(
                    children: [
                      Icon(Icons.launch, size: 14, color: Colors.blue.shade600),
                      const SizedBox(width: 6),
                      Text(
                        'Документация PlatformIO',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _platformioDocs,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
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