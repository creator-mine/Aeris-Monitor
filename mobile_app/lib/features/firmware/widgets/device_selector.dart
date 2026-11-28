import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/firmware_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';

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
                const TrText(
                  'Устройство',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label, icon) in const [
                      ('esp32', 'ESP32', Icons.memory),
                      ('esp32-c3', 'ESP32-C3', Icons.memory),
                      ('esp32-s3', 'ESP32-S3', Icons.memory),
                      ('esp32-c6', 'ESP32-C6', Icons.sensors),
                    ])
                      ChoiceChip(
                        avatar: Icon(icon, size: 18),
                        label: TrText(label),
                        selected: provider.selectedDeviceType == value,
                        onSelected: (_) => provider.selectDeviceType(value),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TrText(
                  switch (provider.selectedDeviceType) {
                    'esp32' =>
                      'Контроллер (ESP32-WROOM-32, 4 МБ): WiFi, MQTT, I2C, UART, SD',
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
