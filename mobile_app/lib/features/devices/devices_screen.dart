import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/devices_provider.dart';
import 'widgets/device_diagnostics_dialog.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/error_widget.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/helpers/device_helper.dart';
import '../../models/device.dart';
import '../logs/logs_screen.dart';

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
            return AppErrorWidget(
              message: provider.error!,
              onRetry: () => provider.loadDevices(),
            );
          }

          if (provider.devices.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices_other, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Нет устройств',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Устройства регистрируются автоматически\nпри подключении к сети',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshDevices(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.devices.length,
              itemBuilder: (context, index) {
                final device = provider.devices[index];
                return _buildDeviceCard(context, device, provider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, Device device, DevicesProvider provider) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: device.isOnline
                ? AppTheme.successColor.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            DeviceHelper.getDeviceIcon(device.type),
            color: device.isOnline ? AppTheme.successColor : Colors.grey,
          ),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'ID: ${device.id}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: device.isOnline ? AppTheme.successColor : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  device.isOnline ? 'Онлайн' : 'Офлайн',
                  style: TextStyle(
                    color: device.isOnline ? AppTheme.successColor : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  device.firmwareVersion == null
                      ? 'fw: —'
                      : 'fw v${device.firmwareVersion}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                if (provider.isOutdated(device)) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.system_update_alt,
                            size: 12, color: AppTheme.warningColor),
                        SizedBox(width: 4),
                        Text(
                          'обновление',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.warningColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            if (device.isOnline)
              const PopupMenuItem(
                value: 'ota',
                child: Row(
                  children: [
                    Icon(Icons.system_update_alt, size: 20),
                    SizedBox(width: 8),
                    Text('Обновить прошивку'),
                  ],
                ),
              ),
            if (device.isOnline && device.ip.isNotEmpty)
              const PopupMenuItem(
                value: 'diagnostics',
                child: Row(
                  children: [
                    Icon(Icons.monitor_heart_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Диагностика'),
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
                    Text('Живые логи'),
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
                    Text('Откатить прошивку'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Удалить', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'delete') {
              _showDeleteConfirmation(context, device, provider);
            } else if (value == 'ota') {
              _showOtaDialog(context, device, provider);
            } else if (value == 'ota_rollback') {
              _showRollbackDialog(context, device, provider);
            } else if (value == 'diagnostics') {
              showDeviceDiagnostics(context, device);
            } else if (value == 'logs') {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => LogsScreen(device: device),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _showOtaDialog(
    BuildContext context,
    Device device,
    DevicesProvider provider,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обновить прошивку?'),
        content: Text(
          'Устройство "${device.name}" скачает последнюю версию прошивки '
          '(${provider.manifestFor(device)?.version ?? '…'}) с сайта и перезагрузится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final message = await provider.sendOtaCommand(device);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
            child: const Text('Обновить'),
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
        title: const Text('Откатить прошивку?'),
        content: Text(
          'Устройство "${device.name}" переключится на предыдущую версию '
          'прошивки и перезагрузится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final message = await provider.sendOtaRollbackCommand(device);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
            child: const Text('Откатить'),
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
        title: const Text('Удалить устройство?'),
        content: Text('Вы уверены, что хотите удалить "${device.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
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
                    content: Text(
                      provider.error ?? 'Не удалось удалить устройство',
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}
