import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firmware_provider.dart';

class DeviceSelector extends StatelessWidget {
  const DeviceSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FirmwareProvider>(
      builder: (context, provider, child) {
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Устройство',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'esp32-c3',
                      label: Text('ESP32-C3'),
                      icon: Icon(Icons.memory),
                    ),
                    ButtonSegment(
                      value: 'esp32-s3',
                      label: Text('ESP32-S3'),
                      icon: Icon(Icons.memory),
                    ),
                    ButtonSegment(
                      value: 'esp32-c6',
                      label: Text('ESP32-C6'),
                      icon: Icon(Icons.sensors),
                    ),
                  ],
                  selected: {provider.selectedDeviceType},
                  onSelectionChanged: (Set<String> selected) {
                    provider.selectDeviceType(selected.first);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  switch (provider.selectedDeviceType) {
                    'esp32-c3' =>
                      'Основной контроллер (LOLIN C3 mini): WiFi, MQTT, I2C, UART',
                    'esp32-s3' =>
                      'Основной контроллер (ESP32-S3 N16R8): WiFi, MQTT, I2C, UART',
                    'esp32-c6' =>
                      'Контроллер (ESP32-C6 N16, 16 МБ): WiFi, MQTT, I2C, UART, реле',
                    _ => 'Неизвестное устройство',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
