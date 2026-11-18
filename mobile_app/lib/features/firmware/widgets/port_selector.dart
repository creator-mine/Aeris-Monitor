import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firmware_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

class PortSelector extends StatelessWidget {
  const PortSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FirmwareProvider>(
      builder: (context, provider, child) {
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
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const TrText(
                      'COM-порт',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: provider.refreshPorts,
                      tooltip: L10n.of(context, 'Обновить список портов'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (provider.availablePorts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TrText(
                            'Устройства не обнаружены. Подключите ESP32 по USB.',
                            style: TextStyle(
                                color: Colors.orange.shade700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (effectivePort != null) ...[
                  _ConnectedDevicePanel(
                    port: effectivePort,
                    description: _descriptionOf(provider, effectivePort),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(effectivePort),
                    initialValue: effectivePort,
                    decoration: InputDecoration(
                      labelText: L10n.of(context, 'Изменить порт'),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: provider.availablePorts.map((port) {
                      final info = provider.portInfoFor(port);
                      return DropdownMenuItem(
                        value: port,
                        child: info != null && info.description.isNotEmpty
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TrText(
                                    port,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  TrText(
                                    info.description,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              )
                            : TrText(port),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        provider.selectPort(value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
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
                  ),
                  if (provider.detectedChip != null) ...[
                    const SizedBox(height: 8),
                    _ChipResultBanner(
                      detected: provider.detectedChip!,
                      matched: provider.detectedChip!.toUpperCase() ==
                          provider.expectedChipName.toUpperCase(),
                      expected: provider.expectedChipName,
                    ),
                  ] else if (provider.detectChipError != null) ...[
                    const SizedBox(height: 8),
                    _ChipErrorBanner(message: provider.detectChipError!),
                  ],
                ],
              ],
            ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.usb, color: Colors.green.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TrText(
                  port,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                TrText(
                  description.isNotEmpty
                      ? description
                      : 'Устройство не определено',
                  style: TextStyle(
                    fontSize: 13,
                    color: description.isNotEmpty
                        ? Colors.green.shade700
                        : Colors.grey[600],
                  ),
                ),
              ],
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
    final color = matched ? Colors.green : Colors.orange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Icon(
            matched ? Icons.check_circle_outline : Icons.error_outline,
            color: color.shade700,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TrText(
              matched
                  ? '$detected · совпадает с выбранным устройством'
                  : '$detected · не совпадает — выбрано $expected',
              style: TextStyle(
                fontSize: 13,
                color: color.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipErrorBanner extends StatelessWidget {
  final String message;

  const _ChipErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: Colors.red.shade700, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: TrText(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
