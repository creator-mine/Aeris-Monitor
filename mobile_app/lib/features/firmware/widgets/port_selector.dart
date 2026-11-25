import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/l10n.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/tr_text.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../providers/firmware_provider.dart';

class PortSelector extends StatelessWidget {
  const PortSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FirmwareProvider>(
      builder: (context, provider, child) {
        final palette = AppPalette.of(context);
        final hasPorts = provider.availablePorts.isNotEmpty;
        final selectedIsValid =
            hasPorts && provider.availablePorts.contains(provider.selectedPort);
        final effectivePort = selectedIsValid
            ? provider.selectedPort
            : (hasPorts ? provider.availablePorts.first : null);

        if (hasPorts &&
            !selectedIsValid &&
            provider.selectedPort != effectivePort) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            provider.selectPort(effectivePort!);
          });
        }

        return AppSurface(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.usb, size: 18, color: palette.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TrText(
                          'COM-порт',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        TrText(
                          'Подключите плату по USB или выберите порт',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: palette.muted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: provider.refreshPorts,
                    tooltip: L10n.of(context, 'Обновить список портов'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (provider.availablePorts.isEmpty)
                _InlineBanner(
                  color: palette.warning,
                  icon: Icons.warning_amber_rounded,
                  text: 'Устройства не обнаружены. Подключите ESP32 по USB.',
                )
              else if (effectivePort != null) ...[
                _ConnectedDevicePanel(
                  port: effectivePort,
                  description: _descriptionOf(provider, effectivePort),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: ValueKey(effectivePort),
                  initialValue: effectivePort,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: L10n.of(context, 'Порт'),
                    prefixIcon: const Icon(Icons.usb, size: 18),
                  ),
                  items: provider.availablePorts.map((port) {
                    final info = provider.portInfoFor(port);
                    final description = info?.description ?? '';
                    return DropdownMenuItem(
                      value: port,
                      child: Text(
                        description.isEmpty ? port : '$port · $description',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) provider.selectPort(value);
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          provider.isDetectingChip ? null : provider.detectChip,
                      icon: provider.isDetectingChip
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.memory_outlined, size: 18),
                      label: TrText(
                        provider.isDetectingChip
                            ? 'Определяю чип…'
                            : 'Определить чип',
                      ),
                    ),
                  ],
                ),
                if (provider.detectedChip != null) ...[
                  const SizedBox(height: 10),
                  _ChipResultBanner(
                    detected: provider.detectedChip!,
                    matched: provider.detectedChip!.toUpperCase() ==
                        provider.expectedChipName.toUpperCase(),
                    expected: provider.expectedChipName,
                  ),
                ] else if (provider.detectChipError != null) ...[
                  const SizedBox(height: 10),
                  _ChipErrorBanner(message: provider.detectChipError!),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

String _descriptionOf(FirmwareProvider provider, String port) {
  final info = provider.portInfoFor(port);
  if (info == null || info.description.isEmpty) return '';
  return info.description;
}

class _ConnectedDevicePanel extends StatelessWidget {
  final String port;
  final String description;

  const _ConnectedDevicePanel({required this.port, required this.description});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.success.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.usb, color: palette.success, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TrText(
                      port,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(
                      label: 'Подключено',
                      color: palette.success,
                      compact: true,
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  TrText(
                    description,
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _InlineBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TrText(
              text,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipResultBanner extends StatelessWidget {
  final String detected;
  final String expected;
  final bool matched;

  const _ChipResultBanner({
    required this.detected,
    required this.expected,
    required this.matched,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = matched ? palette.success : palette.warning;
    return _InlineBanner(
      color: color,
      icon: matched ? Icons.check_circle_outline : Icons.error_outline,
      text: matched
          ? '$detected · совпадает с выбранным устройством'
          : '$detected · не совпадает — выбрано $expected',
    );
  }
}

class _ChipErrorBanner extends StatelessWidget {
  final String message;

  const _ChipErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return _InlineBanner(
      color: AppPalette.of(context).danger,
      icon: Icons.warning_amber_rounded,
      text: message,
    );
  }
}
