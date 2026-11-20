import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/app_update_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/i18n/l10n.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/tr_text.dart';
import '../providers/update_provider.dart';

/// "Обновления" card: automatic check toggle and a manual check row.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final update = context.watch<UpdateProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrText(
          'Обновления',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
        ),
        const SizedBox(height: 12),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: AppTheme.cardDecoration(darkMode: isDark),
          // ListTiles paint ink on the nearest Material; without this wrapper
          // the decorated container hides the splash (and Flutter asserts).
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                SwitchListTile(
                  secondary:
                      const Icon(Icons.sync, color: AppTheme.primaryColor),
                  title: const TrText('Проверять обновления'),
                  subtitle: const TrText(
                    'Автоматически раз в несколько часов через GitHub Releases',
                  ),
                  value: update.autoCheck,
                  onChanged: (value) {
                    unawaited(update.setAutoCheck(value));
                    // Turning the switch back on should not wait for the
                    // 30-minute timer tick to run the first check.
                    if (value) unawaited(update.maybeAutoCheck());
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Theme.of(context)
                      .dividerColor
                      .withValues(alpha: isDark ? 0.4 : 0.25),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.cloud_download_outlined,
                    color: AppTheme.primaryColor,
                  ),
                  title: const TrText('Проверить обновления'),
                  subtitle: Text(
                    _subtitle(context, update),
                    style: update.state == UpdateCheckState.failed
                        ? TextStyle(color: Theme.of(context).colorScheme.error)
                        : null,
                  ),
                  trailing: update.checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap:
                      update.checking ? null : () => _checkNow(context, update),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _subtitle(BuildContext context, UpdateProvider update) {
    switch (update.state) {
      case UpdateCheckState.checking:
        return L10n.of(context, 'Проверяю GitHub Releases…');
      case UpdateCheckState.updateAvailable:
        return '${L10n.of(context, 'Доступна версия')} '
            '${update.availableVersion}';
      case UpdateCheckState.upToDate:
        return L10n.of(context, 'Установлена последняя версия');
      case UpdateCheckState.failed:
        return update.error ??
            L10n.of(context, 'Не удалось проверить обновления');
      case UpdateCheckState.idle:
        final last = update.lastCheckAt;
        if (last != null) {
          return '${L10n.of(context, 'Проверено')}: ${_formatDate(last)}';
        }
        return L10n.of(context, 'Проверить наличие новой версии');
    }
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _checkNow(BuildContext context, UpdateProvider update) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await update.checkNow();
    if (!context.mounted) return;

    if (update.state == UpdateCheckState.failed) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            update.error ?? L10n.of(context, 'Не удалось проверить обновления'),
          ),
        ),
      );
      return;
    }
    final release = update.available;
    if (release == null) {
      messenger?.showSnackBar(
        const SnackBar(content: TrText('Установлена последняя версия')),
      );
      return;
    }
    await showAppUpdateDialog(context, release);
  }
}

/// Release details with links to the GitHub page and the platform installer.
Future<void> showAppUpdateDialog(
  BuildContext context,
  AppRelease release,
) async {
  // Only offer the installer we actually ship: .apk on Android, .exe on
  // Windows. Other platforms get the release page instead.
  final String? installer;
  if (kIsWeb) {
    installer = null;
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    installer = release.installerUrl(android: true);
  } else if (defaultTargetPlatform == TargetPlatform.windows) {
    installer = release.installerUrl(android: false);
  } else {
    installer = null;
  }
  final notes = _cleanNotes(release.notes);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final installUrl = installer;
      return AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: AppTheme.primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${L10n.of(dialogContext, 'Доступна версия')} '
                '${release.version}',
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${L10n.of(dialogContext, 'Установлено')}: '
                '${AppConfig.appVersion}',
              ),
              const SizedBox(height: 4),
              Text('${L10n.of(dialogContext, 'Новое')}: ${release.version}'),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  notes,
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const TrText('Позже'),
          ),
          if (release.htmlUrl.isNotEmpty)
            TextButton(
              onPressed: () => _openLink(dialogContext, release.htmlUrl),
              child: const TrText('Открыть релиз'),
            ),
          if (installUrl != null)
            FilledButton.icon(
              onPressed: () => _openLink(dialogContext, installUrl),
              icon: const Icon(Icons.download, size: 18),
              label: const TrText('Скачать'),
            ),
        ],
      );
    },
  );
}

/// Trims markdown noise so release notes read fine in a small dialog.
String _cleanNotes(String raw) {
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst(RegExp(r'^#+\s*'), ''))
      .map((line) => line.replaceFirst(RegExp(r'^[-*]\s*'), '• '))
      .toList();
  final text = lines.join('\n');
  return text.length > 600 ? '${text.substring(0, 600)}…' : text;
}

Future<void> _openLink(BuildContext context, String url) async {
  final message = L10n.of(context, 'Не удалось открыть ссылку');
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
