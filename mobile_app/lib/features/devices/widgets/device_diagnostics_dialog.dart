import 'package:flutter/material.dart';
import '../../../core/api/direct_device_client.dart';
import '../../../models/device.dart';
import '../../logs/logs_screen.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

/// Fetches live status + modules from a device over HTTP and shows a
/// diagnostics sheet (uptime, heap, WiFi, firmware, sensor modules),
/// with quick actions: live logs and OTA.
Future<void> showDeviceDiagnostics(BuildContext context, Device device) {
  final client = DirectDeviceClient(baseUrl: device.httpBaseUrl!);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DiagnosticsSheet(
      device: device,
      client: client,
    ),
  ).whenComplete(client.dispose);
}

class _DiagnosticsSheet extends StatefulWidget {
  final Device device;
  final DirectDeviceClient client;

  const _DiagnosticsSheet({required this.device, required this.client});

  @override
  State<_DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<_DiagnosticsSheet> {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _modules = const [];
  bool _loading = true;
  String? _error;

  Device get _device => widget.device;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.client.getStatus();
      List<Map<String, dynamic>> modules = const [];
      try {
        final response = await widget.client.getModules();
        modules = response.map((m) => m.toJson()).toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _status = status;
        _modules = modules;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TrText(
                    'Диагностика · ${_device.name}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: L10n.of(context, 'Живые логи'),
                  icon: const Icon(Icons.terminal),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => LogsScreen(device: _device),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: L10n.of(context, 'Обновить'),
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(
                          controller: scrollController,
                          children: [
                            TrText(
                              'Не удалось получить данные: $_error',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const TrText('Повторить'),
                            ),
                          ],
                        )
                      : _buildContent(scrollController),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    final status = _status ?? const <String, dynamic>{};
    final uptime = status['uptime'] is num
        ? _formatUptime((status['uptime'] as num).toInt())
        : null;

    final rows = <(String, String)>[
      ('ID', _device.id),
      ('IP', status['ip'] as String? ?? _device.ip),
      ('Wi-Fi', status['wifi_connected'] == true ? 'подключено' : 'нет'),
      ('Питание', _device.isOnline ? 'онлайн' : 'офлайн'),
      ('Uptime', uptime ?? '—'),
      (
        'Свободная память',
        status['free_heap'] is num
            ? _formatBytes((status['free_heap'] as num).toInt())
            : '—'
      ),
      if (status['rssi'] is num)
        ('RSSI', '${(status['rssi'] as num).toInt()} dBm'),
      if (status['chip_temp'] is num)
        (
          'Температура чипа',
          '${(status['chip_temp'] as num).toStringAsFixed(1)} °C'
        ),
      ('Время синхронизировано', status['time_synced'] == true ? 'да' : 'нет'),
      (
        'Прошивка',
        status['firmware'] as String? ?? _device.firmwareVersion ?? '—'
      ),
      ('Модули', '${_modules.length}'),
    ];

    return ListView(
      controller: scrollController,
      children: [
        for (final (label, value) in rows) _infoRow(label, value),
        const SizedBox(height: 16),
        TrText(
          'Модули устройства',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        if (_modules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: TrText('Модули не отвечают',
                style: TextStyle(color: Colors.grey)),
          )
        else
          ..._modules.map(_buildModuleCard),
      ],
    );
  }

  Widget _buildModuleCard(Map<String, dynamic> module) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.memory,
          color: module['status'] == 'online' ? Colors.green : Colors.grey,
        ),
        title: TrText('${module['name'] ?? ''} (${module['id'] ?? ''})'),
        subtitle: TrText(
          'тип: ${module['type'] ?? '—'} · статус: ${module['status'] ?? '—'}',
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: TrText(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: TrText(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatUptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (days > 0) return '$days д $hours ч $minutes м';
    if (hours > 0) return '$hours ч $minutes м $secs с';
    if (minutes > 0) return '$minutes м $secs с';
    return '$secs с';
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    return '$bytes Б';
  }
}
