import 'package:flutter/material.dart';

class DeviceHelper {
  static IconData getDeviceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'esp32':
        return Icons.memory;
      case 'esp32c3':
        return Icons.memory;
      case 'esp32c6':
        return Icons.developer_board;
      case 'esp32s3':
        return Icons.developer_board;
      default:
        return Icons.devices_other;
    }
  }
}
