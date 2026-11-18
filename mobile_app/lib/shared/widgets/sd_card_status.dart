import 'package:flutter/material.dart';

import '../../core/i18n/l10n.dart';
import '../../models/sd_card_info.dart';
import '../theme/app_theme.dart';
import '../utils/byte_format.dart';
import 'tr_text.dart';

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

    return Container(
      decoration: AppTheme.cardDecoration(darkMode: isDark),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sd_storage_outlined,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: TrText(
                  'Карта памяти',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TrText(
                  status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: status.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (info == null || !info!.isOk) ...[
            TrText(
              status.hint,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ] else ...[
            Row(
              children: [
                _metric(
                  'Занято',
                  formatBytes(info!.usedBytes, language: language),
                ),
                const SizedBox(width: 20),
                _metric(
                  'Свободно',
                  formatBytes(info!.freeBytes, language: language),
                ),
                const SizedBox(width: 20),
                _metric(
                  'Всего',
                  formatBytes(info!.totalBytes, language: language),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: info!.usedFraction,
                minHeight: 8,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                color: status.color,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TrText(
                  '${info!.usedPercent}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: status.color,
                  ),
                ),
                const Spacer(),
                if (info!.cardType.isNotEmpty)
                  TrText(
                    '${info!.cardType} · '
                    '${formatBytes(info!.totalBytes, language: language)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrText(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  _SdStatus _statusOf(BuildContext context) {
    if (info == null) {
      return _SdStatus(
        label: L10n.of(context, 'Нет данных'),
        hint: L10n.of(context, 'Устройство не сообщает состояние карты.'),
        color: Colors.grey,
      );
    }
    switch (info!.status) {
      case 'ok':
        return _SdStatus(
          label: L10n.of(context, 'Работает'),
          hint: '',
          color: AppTheme.successColor,
        );
      case 'mount_failed':
        return _SdStatus(
          label: L10n.of(context, 'Ошибка'),
          hint: L10n.of(
            context,
            'Файловая система не поддерживается. '
            'Отформатируйте карту в FAT32.',
          ),
          color: AppTheme.warningColor,
        );
      default:
        return _SdStatus(
          label: L10n.of(context, 'Нет карты'),
          hint: L10n.of(
            context,
            'Карта не вставлена. Вставьте microSD-карту (FAT32).',
          ),
          color: Colors.grey,
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
