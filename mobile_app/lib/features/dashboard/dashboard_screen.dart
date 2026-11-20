import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'providers/dashboard_provider.dart';
import 'widgets/device_card.dart';
import 'widgets/sensor_tile.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/error_widget.dart';
import '../../shared/widgets/sd_card_status.dart';
import '../../core/config/app_config.dart';
import '../../core/config/connection_mode.dart';
import '../../models/device.dart';
import '../devices/widgets/rename_device_dialog.dart';
import '../wifi/wifi_screen.dart';
import '../../core/api/direct_device_client.dart';
import '../../core/api/api_client.dart';
import '../../core/api/wifi_transport.dart';
import '../../core/utils/version.dart';
import '../settings/providers/settings_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dashboard = context.read<DashboardProvider>();
      dashboard.loadDevices();
      final settings = context.read<SettingsProvider>();
      if (settings.connectionMode != dashboard.connectionMode) {
        dashboard.setConnectionMode(settings.connectionMode);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Панель управления',
      actions: [
        Consumer<DashboardProvider>(
          builder: (context, provider, child) {
            return PopupMenuButton<ConnectionMode>(
              icon: Icon(
                switch (provider.connectionMode) {
                  ConnectionMode.auto => Icons.compare_arrows,
                  ConnectionMode.lanDirect => Icons.lan,
                  ConnectionMode.mqtt => Icons.cloud_queue,
                },
              ),
              tooltip: L10n.of(context, 'Режим соединения'),
              onSelected: (mode) {
                provider.setConnectionMode(mode);
                context.read<SettingsProvider>().setConnectionMode(mode);
              },
              itemBuilder: (context) => [
                for (final mode in ConnectionMode.values)
                  PopupMenuItem(
                    value: mode,
                    child: Row(
                      children: [
                        Icon(
                          mode == provider.connectionMode
                              ? Icons.check
                              : Icons.settings_ethernet,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        TrText(mode.label),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            context.read<DashboardProvider>().refreshData();
          },
        ),
      ],
      body: Consumer<DashboardProvider>(
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
                  TrText(
                    'Нет подключённых устройств',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDevicesSection(context, provider),
                  const SizedBox(height: 24),
                  if (provider.selectedDevice != null) ...[
                    _buildSelectedDeviceSection(context, provider),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDevicesSection(
      BuildContext context, DashboardProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TrText(
              'Устройства',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            TrText(
              '${provider.onlineDevices.length}/${provider.devices.length} онлайн',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: provider.devices.length,
            itemBuilder: (context, index) {
              final device = provider.devices[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: DeviceCard(
                  device: device,
                  isSelected: provider.selectedDevice?.id == device.id,
                  onTap: () => provider.selectDevice(device),
                  onRename: () => _renameDevice(context, provider, device),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _renameDevice(
    BuildContext context,
    DashboardProvider provider,
    Device device,
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

  Widget _buildSelectedDeviceSection(
      BuildContext context, DashboardProvider provider) {
    final device = provider.selectedDevice!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TrText(
                device.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            IconButton(
              tooltip: L10n.of(context, 'Переименовать устройство'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _renameDevice(context, provider, device),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            TrText(
              'Последнее обновление: ${DateFormat('dd.MM.yyyy HH:mm').format(device.lastSeen)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const SizedBox(width: 8),
            if (provider.activeChannelLabel != null)
              Chip(
                label: TrText(provider.activeChannelLabel!),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                labelStyle: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final device = provider.selectedDevice;
                final baseUrl = device?.httpBaseUrl;
                final hasWifiManager = device?.firmwareVersion == null ||
                    compareVersions(device?.firmwareVersion, '1.3.7') >= 0;
                if (device != null &&
                    device.isOnline &&
                    baseUrl != null &&
                    hasWifiManager) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WifiScreen(
                        transport: HttpWifiTransport(
                          DirectDeviceClient(baseUrl: baseUrl),
                        ),
                      ),
                    ),
                  );
                  return;
                }

                if (device != null && hasWifiManager) {
                  final choice = await showModalBottomSheet<String>(
                    context: context,
                    showDragHandle: true,
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.cloud_outlined),
                            title: const Text('Через сервер'),
                            subtitle: const Text(
                                'Переключение на сохранённую сеть с подтверждением'),
                            onTap: () => Navigator.pop(context, 'remote'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.wifi),
                            title: const Text('Точка настройки'),
                            subtitle: const Text(
                                'Aeris-Setup-XXXX на 5 минут'),
                            onTap: () => Navigator.pop(context, 'ap'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (!context.mounted) return;
                  if (choice == 'remote') {
                    final api = context.read<ApiClient>();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WifiScreen(
                          title: 'Wi-Fi (удалённо)',
                          transport: ServerWifiTransport(api, device.id),
                        ),
                      ),
                    );
                    return;
                  }
                }

                final sent = provider.sendCommand('wifi_reconfigure');
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: TrText(
                      sent
                          ? 'Устройство перейдёт в режим настройки Wi-Fi. '
                              'Подключитесь к его сети Aeris-Setup-XXXX и откройте http://192.168.4.1'
                          : 'Нет связи с устройством: команда не отправлена',
                    ),
                    duration: const Duration(seconds: 6),
                  ),
                );
              },
              icon: const Icon(Icons.wifi, size: 20),
              label: const TrText('Настроить Wi-Fi'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {
                final sent = provider.sendCommand('restart');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: TrText(
                      sent
                          ? 'Команда перезагрузки отправлена'
                          : 'Нет связи с устройством: команда не отправлена',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.restart_alt, size: 20),
              label: const TrText('Перезагрузить'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSensorsGrid(context, provider),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SdCardStatusCard(info: provider.sdCard),
          ),
        ),
      ],
    );
  }

  Widget _buildSensorsGrid(BuildContext context, DashboardProvider provider) {
    final device = provider.selectedDevice!;
    var metrics = device.allMetrics;

    if (metrics.isEmpty) {
      metrics = AppConfig.defaultSensorNames.keys
          .map((key) => MetricInfo(
                key: key,
                name: AppConfig.defaultSensorNames[key] ?? key,
                unit: AppConfig.defaultSensorUnits[key] ?? '',
              ))
          .toList();
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 140,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final metric = metrics[index];
        final value = provider.getSensorValue(metric.key);

        return SensorTile(
          name: AppConfig.defaultSensorNames[metric.key] ?? metric.name,
          value: value,
          unit: metric.unit,
          icon: AppConfig.metricIcon(metric.key),
        );
      },
    );
  }
}
