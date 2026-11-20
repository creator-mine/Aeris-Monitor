class WifiProfile {
  final int id;
  final String ssid;
  final int priority;
  final bool enabled;
  final bool connected;
  final int? rssi;

  const WifiProfile({
    required this.id,
    required this.ssid,
    required this.priority,
    required this.enabled,
    required this.connected,
    this.rssi,
  });

  factory WifiProfile.fromJson(Map<String, dynamic> json) {
    return WifiProfile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      ssid: (json['ssid'] as String?) ?? '',
      priority: (json['priority'] as num?)?.toInt() ?? 1,
      enabled: json['enabled'] as bool? ?? true,
      connected: json['connected'] as bool? ?? false,
      rssi: (json['rssi'] as num?)?.toInt(),
    );
  }
}

class WifiStatus {
  final bool connected;
  final int activeId;
  final String ssid;
  final int rssi;
  final String ip;
  final bool manual;
  final int manualId;
  final int used;
  final int max;
  final List<WifiProfile> profiles;

  const WifiStatus({
    required this.connected,
    required this.activeId,
    required this.ssid,
    required this.rssi,
    required this.ip,
    required this.manual,
    required this.manualId,
    required this.used,
    required this.max,
    required this.profiles,
  });

  factory WifiStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['profiles'];
    return WifiStatus(
      connected: json['connected'] as bool? ?? false,
      activeId: (json['id'] as num?)?.toInt() ?? 0,
      ssid: (json['ssid'] as String?) ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? 0,
      ip: (json['ip'] as String?) ?? '',
      manual: json['manual'] as bool? ?? false,
      manualId: (json['manual_id'] as num?)?.toInt() ?? 0,
      used: (json['used'] as num?)?.toInt() ?? 0,
      max: (json['max'] as num?)?.toInt() ?? 8,
      profiles: raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .map(WifiProfile.fromJson)
              .toList()
          : const [],
    );
  }
}

class WifiScanEntry {
  final String ssid;
  final int rssi;
  final bool secure;
  final int channel;
  final String bssid;

  const WifiScanEntry({
    required this.ssid,
    required this.rssi,
    required this.secure,
    required this.channel,
    required this.bssid,
  });

  factory WifiScanEntry.fromJson(Map<String, dynamic> json) {
    return WifiScanEntry(
      ssid: (json['ssid'] as String?) ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? -127,
      secure: json['secure'] as bool? ?? false,
      channel: (json['channel'] as num?)?.toInt() ?? 0,
      bssid: (json['bssid'] as String?) ?? '',
    );
  }
}
