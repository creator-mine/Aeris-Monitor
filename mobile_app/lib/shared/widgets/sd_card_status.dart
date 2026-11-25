import 'package:flutter/material.dart';

import '../../core/i18n/l10n.dart';
import '../../models/sd_card_info.dart';
import '../theme/app_theme.dart';
import '../utils/byte_format.dart';
import 'tr_text.dart';
import 'ui_kit.dart';

/// Shared SD-card summary: state badge, usage bar and capacity figures.
/// Shown on the dashboard and in the device diagnostics sheet.
class SdCardStatusCard extends StatelessWidget {
  final SdCardInfo? info;

  const SdCardStatusCard({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = _statusOf(context);
    final palette = AppPalette.of(context);

    return Container(
      decoration: AppTheme.cardDecoration(darkMode: isDark),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sd_storage_outlined,
                color: palette.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: TrText(
                  'Карта памяти',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              StatusPill(
                  label: status.label, color: status.color, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          if (info == null || !info!.isOk) ...[
            TrText(
              status.hint,
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ] else ...[
            Row(
              children: [
                _metric(
                  context,
                  'Занято',
                  formatBytes(info!.usedBytes, language: language),
                ),
                const SizedBox(width: 24),
                _metric(
                  context,
                  'Свободно',
                  formatBytes(info!.freeBytes, language: language),
                ),
                const SizedBox(width: 24),
                _metric(
                  context,
                  'Всего',
                  formatBytes(info!.totalBytes, language: language),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: info!.usedFraction,
                minHeight: 8,
                backgroundColor: palette.surfaceAlt,
                color: status.color,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                TrText(
                  '${info!.usedPercent}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: status.color,
                  ),
                ),
                const Spacer(),
                if (info!.cardType.isNotEmpty)
                  TrText(
                    '${info!.cardType} · '
                    '${formatBytes(info!.totalBytes, language: language)}',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrText(
          label,
          style: TextStyle(fontSize: 11, color: palette.muted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: palette.text,
          ),
        ),
      ],
    );
  }

  _SdStatus _statusOf(BuildContext context) {
    final palette = AppPalette.of(context);
    if (info == null) {
      return _SdStatus(
        label: L10n.of(context, 'Нет данных'),
        hint: L10n.of(context, 'Устройство не сообщает состояние карты.'),
        color: palette.faint,
      );
    }
    switch (info!.status) {
      case 'ok':
        return _SdStatus(
          label: L10n.of(context, 'Работает'),
          hint: '',
          color: palette.success,
        );
      case 'mount_failed':
        return _SdStatus(
          label: L10n.of(context, 'Ошибка'),
          hint: L10n.of(
            context,
            'Файловая система не поддерживается. '
            'Отформатируйте карту в FAT32.',
          ),
          color: palette.warning,
        );
      default:
        return _SdStatus(
          label: L10n.of(context, 'Нет карты'),
          hint: L10n.of(
            context,
            'Карта не вставлена. Вставьте microSD-карту (FAT32).',
          ),
          color: palette.faint,
        );
    }
  }
}

class _SdStatus {
  final String label;
  final String hint;
  final Color color;

  const _SdStatus({
    required this.label,
    required this.hint,
    required this.color,
  });
}
