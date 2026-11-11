import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/mqtt_client.dart';
import '../../devices/providers/devices_provider.dart';

/// Android-only firmware panel: no PlatformIO and no USB flashing.
/// The device is told to update itself over Wi-Fi via MQTT commands
/// (`ota`, `rollback`, `restart`), which the firmware already understands.
class AndroidOtaCard extends StatefulWidget {
  const AndroidOtaCard({super.key});

  @override
  State<AndroidOtaCard> createState() => _AndroidOtaCardState();
}

class _AndroidOtaCardState extends State<AndroidOtaCard> {
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DevicesProvider>().loadDevices();
    });
  }

  void _send(String command, {bool force = false}) {
    final id = _deviceId;
    if (id == null) return;

    final mqtt = context.read<MqttService>();
    if (!mqtt.isConnected) {
      _snack('Нет соединения с MQTT-брокером. Проверьте настройки.');
      return;
    }

    final payload = <String, dynamic>{'command': command};
    if (force) payload['force'] = true;
    mqtt.publishCommand(id, payload);
    _snack('Команда «$command» отправлена устройству $id');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DevicesProvider>(
      builder: (context, provider, _) {
        final devices = provider.devices;
        if (devices.isEmpty) {
          return Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Обновление по воздуху',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    provider.isLoading
                        ? 'Загрузка устройств…'
                        : 'Устройства не найдены. Откройте вкладку «Устройства» и обновите список.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        final selected = devices.firstWhere(
          (d) => d.id == _deviceId,
          orElse: () => devices.first,
        );
        _deviceId = selected.id;

        final current = selected.firmwareVersion ?? '—';
        final published = provider.manifestFor(selected)?.version ?? '—';
        final mqtt = context.watch<MqttService>();
        final canSend = mqtt.isConnected;

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Обновление по воздуху',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Устройство скачает прошивку само. USB и сборка не нужны.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selected.id,
                  decoration: const InputDecoration(
                    labelText: 'Устройство',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: devices
                      .map(
                        (d) => DropdownMenuItem(
                          value: d.id,
                          child: Text('${d.name} (${d.id})'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _deviceId = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _InfoTile(
                        label: 'Сейчас',
                        value: current,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InfoTile(
                        label: 'Опубликовано',
                        value: published,
                      ),
                    ),
                  ],
                ),
                if (!canSend) ...[
                  const SizedBox(height: 8),
                  Text(
                    'MQTT не подключён — команды недоступны.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canSend ? () => _send('ota') : null,
                    icon: const Icon(Icons.system_update),
                    label: const Text('Обновить'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canSend ? () => _send('rollback') : null,
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Откатить'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canSend ? () => _send('restart') : null,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Перезагрузить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
