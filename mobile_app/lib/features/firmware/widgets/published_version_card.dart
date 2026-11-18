import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firmware_provider.dart';
import '../../../core/utils/version.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

/// Real published-version info from the OTA site (/fw/version.json) plus
/// the freshness of the local project source against it.
class PublishedVersionCard extends StatelessWidget {
  const PublishedVersionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FirmwareProvider>();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_done_outlined, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: TrText(
                    'Опубликованная версия (OTA)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (provider.isCheckingServer)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: L10n.of(context, 'Проверить на сайте'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: provider.fetchServerManifest,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildContent(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(FirmwareProvider provider) {
    final manifest = provider.serverManifest;

    if (manifest == null) {
      if (provider.isCheckingServer) {
        return const TrText('Проверка актуальной версии на сайте...',
            style: TextStyle(color: Colors.grey));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrText(
            provider.serverCheckError ?? 'Версия на сайте не проверена.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (provider.serverCheckError != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: provider.fetchServerManifest,
              icon: const Icon(Icons.refresh, size: 16),
              label: const TrText('Повторить'),
            ),
          ],
        ],
      );
    }

    final freshness = provider.freshness;
    final (color, icon, label) = switch (freshness) {
      FirmwareFreshness.outdated => (
          AppTheme.errorColor,
          Icons.arrow_upward,
          'Локальная сборка устарела'
        ),
      FirmwareFreshness.latest => (
          AppTheme.successColor,
          Icons.check_circle_outline,
          'Сборка совпадает с опубликованной'
        ),
      FirmwareFreshness.newer => (
          Colors.blue,
          Icons.published_with_changes,
          'Локальная сборка новее опубликованной'
        ),
      FirmwareFreshness.unknown => (
          Colors.grey,
          Icons.help_outline,
          'Актуальность не определена'
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TrText(
              'v${manifest.version}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            _pill(manifest.deviceType),
            TrText(
              'сборка ${manifest.buildDateLabel}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        if (manifest.sha256 != null && manifest.sha256!.isNotEmpty) ...[
          const SizedBox(height: 4),
          TrText(
            'sha256: ${_shortHash(manifest.sha256!)}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: TrText(
                  '$label: локально '
                  '${provider.localVersion == null || provider.localVersion!.isEmpty ? '—' : 'v${provider.localVersion}'}'
                  ', на сайте v${manifest.version}',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Abbreviates a SHA-256 hash without assuming a 64-char string, so a
  /// malformed/short manifest can never crash the firmware screen.
  String _shortHash(String hash) {
    if (hash.length <= 20) return hash;
    return '${hash.substring(0, 16)}…${hash.substring(hash.length - 16)}';
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TrText(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
      ),
    );
  }
}
