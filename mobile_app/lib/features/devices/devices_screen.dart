import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/devices_provider.dart';
import 'widgets/device_diagnostics_dialog.dart';
import 'widgets/rename_device_dialog.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/ui_kit.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/helpers/device_helper.dart';
import '../../core/i18n/l10n.dart';
import '../../models/device.dart';
import '../logs/logs_screen.dart';
import 'package:aeris/shared/widgets/tr_text.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<DevicesProvider>();
      provider.loadDevices();
      provider.loadManifest();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Устройства',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            context.read<DevicesProvider>().refreshDevices();
          },
        ),
      ],
      body: Consumer<DevicesProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.devices.isEmpty) {
            return const LoadingIndicator(message: 'Загрузка устройств...');
          }

          if (provider.error != null && provider.devices.isEmpty) {
            return EmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'Нет связи с устройствами',
              message: provider.error!,
              action: FilledButton.icon(
                onPressed: () => provider.loadDevices(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const TrText('Повторить'),
              ),
            );
          }

          if (provider.devices.isEmpty) {
            return EmptyState(
              icon: Icons.devices_other,
              title: 'Нет устройств',
              message: 'Устройства находятся автоматически в локальной сети '
                  'или через сервер.',
              action: FilledButton.icon(
                onPressed: () => provider.refreshDevices(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const TrText('Искать устройства'),
              ),
            );
          }

          final wide = MediaQuery.sizeOf(context).width >= 900;
          return RefreshIndicator(
            onRefresh: () => provider.refreshDevices(),
            child: wide
                ? GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 430,
                      mainAxisExtent: 200,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: provider.devices.length,
                    itemBuilder: (context, index) {
                      return _buildDeviceCard(
                        context,
                        provider.devices[index],
                        provider,
                      );
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: provider.devices.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildDeviceCard(
                          context,
                          provider.devices[index],
                          provider,
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(
      BuildContext context, Device device, DevicesProvider provider) {
    final palette = AppPalette.of(context);
    final online = device.isOnline;

    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (online ? palette.success : palette.muted)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: (online ? palette.success : palette.border)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  DeviceHelper.getDeviceIcon(device.type),
                  color: online ? palette.success : palette.muted,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TrText(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    TrText(
                      device.type.toUpperCase(),
                      style: TextStyle(
                        color: palette.faint,
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDeviceMenu(context, device, provider),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                label: online ? 'Онлайн' : 'Офлайн',
                color: online ? palette.success : palette.faint,
                compact: true,
              ),
              _deviceMeta(context, Icons.tag, device.id),
              _deviceMeta(
                context,
                Icons.memory_outlined,
                device.firmwareVersion == null
                    ? 'Прошивка: —'
                    : 'v${device.firmwareVersion}',
              ),
              if (device.ip.isNotEmpty)
                _deviceMeta(context, Icons.lan_outlined, device.ip),
            ],
          ),
          if (provider.isOutdated(device)) ...[
            const SizedBox(height: 10),
            StatusPill(
              label: 'обновление',
              color: palette.warning,
              icon: Icons.system_update_alt,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceMeta(BuildContext context, IconData icon, String text) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: palette.faint),
        const SizedBox(width: 5),
        TrText(
          text,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildDeviceMenu(
    BuildContext context,
    Device device,
    DevicesProvider provider,
  ) {
    return PopupMenuButton<String>(
      tooltip: L10n.of(context, 'Действия'),
      icon: const Icon(Icons.more_vert, size: 20),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20),
              SizedBox(width: 8),
              TrText('Переименовать устройство'),
            ],
          ),
        ),
        if (device.isOnline)
          const PopupMenuItem(
            value: 'ota',
            child: Row(
              children: [
                Icon(Icons.system_update_alt, size: 20),
                SizedBox(width: 8),
                TrText('Обновить прошивку'),
              ],
            ),
          ),
        if (device.isOnline)
          const PopupMenuItem(
            value: 'diagnostics',
            child: Row(
              children: [
                Icon(Icons.monitor_heart_outlined, size: 20),
                SizedBox(width: 8),
                TrText('Диагностика'),
              ],
            ),
          ),
        if (device.isOnline && device.ip.isNotEmpty)
          const PopupMenuItem(
            value: 'logs',
            child: Row(
              children: [
                Icon(Icons.terminal, size: 20),
                SizedBox(width: 8),
                TrText('Живые логи'),
              ],
            ),
          ),
        if (device.isOnline)
          const PopupMenuItem(
            value: 'ota_rollback',
            child: Row(
              children: [
                Icon(Icons.settings_backup_restore, size: 20),
                SizedBox(width: 8),
                TrText('Откатить прошивку'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: Colors.red),
              SizedBox(width: 8),
              TrText('Удалить', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'rename') {
          _renameDevice(context, device, provider);
        } else if (value == 'delete') {
          _showDeleteConfirmation(context, device, provider);
        } else if (value == 'ota') {
          _showOtaDialog(context, device, provider);
        } else if (value == 'ota_rollback') {
          _showRollbackDialog(context, device, provider);
        } else if (value == 'diagnostics') {
          showDeviceDiagnostics(
            context,
            device,
            mqttStatus: provider.latestStatusFor(device.id),
            mqttSdCard: provider.sdCardFor(device.id),
          );
        } else if (value == 'logs') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => LogsScreen(device: device),
            ),
          );
        }
      },
    );
  }

  Future<void> _renameDevice(
    BuildContext context,
    Device device,
    DevicesProvider provider,
  ) async {
    final name = await showRenameDeviceDialog(context, device);
    if (name == null || !context.mounted) return;
    final updated = await provider.renameDevice(device, name);
    if (!context.mounted) return;
    if (updated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TrText('Не удалось переименовать устройство'),
        ),
      );
    }
  }

  Future<void> _showOtaDialog(
    BuildContext context,
    Device device,
    DevicesProvider provider,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const TrText('Обновить прошивку?'),
        content: TrText(
          'Устройство "${device.name}" скачает последнюю версию прошивки '
          '(${provider.manifestFor(device)?.version ?? '…'}) с сайта и перезагрузится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TrText('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final message = await provider.sendOtaCommand(device);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: TrText(message)),
              );
            },
            child: const TrText('Обновить'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRollbackDialog(
    BuildContext context,
    Device device,
    DevicesProvider provider,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const TrText('Откатить прошивку?'),
        content: TrText(
          'Устройство "${device.name}" переключится на предыдущую версию '
          'прошивки и перезагрузится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TrText('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final message = await provider.sendOtaRollbackCommand(device);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: TrText(message)),
              );
            },
            child: const TrText('Откатить'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    Device device,
    DevicesProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const TrText('Удалить устройство?'),
        content: TrText('Вы уверены, что хотите удалить "${device.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TrText('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await provider.deleteDevice(device.id);
              if (!context.mounted) return;
              if (success) {
                Navigator.of(context).pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: TrText(
                      provider.error ?? 'Не удалось удалить устройство',
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const TrText('Удалить'),
          ),
        ],
      ),
    );
  }
}
