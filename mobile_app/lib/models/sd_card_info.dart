import 'package:equatable/equatable.dart';

/// SD-card state reported by `/api/v1/sd/info` and embedded in the device
/// status frame (`status["sd"]`).
///
/// Firmware 1.3.6 sends:
///   {"status":"ok","mounted":true,"card_detected":true,"type":"SDHC",
///    "total_bytes":..., "used_bytes":..., "free_bytes":..., "used_pct":9}
class SdCardInfo extends Equatable {
  final String status;
  final bool mounted;
  final bool cardDetected;
  final String cardType;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int? reportedUsedPercent;

  const SdCardInfo({
    required this.status,
    required this.mounted,
    required this.cardDetected,
    required this.cardType,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    this.reportedUsedPercent,
  });

  factory SdCardInfo.fromJson(Map<String, dynamic> json) {
    int readBytes(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    final mounted = json['mounted'] == true;
    final cardType = (json['type'] ?? json['card_type'] ?? '').toString();
    final cardDetected = json['card_detected'] == true || cardType.isNotEmpty;
    final total = readBytes('total_bytes');
    final used = readBytes('used_bytes');
    final free = readBytes('free_bytes');
    final reportedPct = (json['used_pct'] as num?)?.toInt();

    final status = (json['status'] as String?) ??
        (mounted ? 'ok' : (cardDetected ? 'mount_failed' : 'no_card'));

    return SdCardInfo(
      status: status,
      mounted: mounted,
      cardDetected: cardDetected,
      cardType: cardType,
      totalBytes: total,
      usedBytes: used,
      freeBytes: free > 0 ? free : (used < total ? total - used : 0),
      reportedUsedPercent: reportedPct,
    );
  }

  /// Returns the SD block from a status frame, tolerating older firmware that
  /// still reports flat `sd_*` fields (1.3.6 uses a nested `sd` object).
  static SdCardInfo? tryFromStatus(Map<String, dynamic> status) {
    final nested = status['sd'];
    if (nested is Map<String, dynamic>) return SdCardInfo.fromJson(nested);

    if (status.containsKey('sd_mounted') || status.containsKey('sd_status')) {
      return SdCardInfo.fromJson({
        'status': status['sd_status'],
        'mounted': status['sd_mounted'],
        'card_detected': status['sd_detected'],
        'type': status['sd_type'],
        'card_bytes': status['sd_card_bytes'],
        'total_bytes': status['sd_total_bytes'],
        'used_bytes': status['sd_used_bytes'],
        'free_bytes': status['sd_free_bytes'],
        'used_pct': status['sd_used_pct'],
      });
    }

    return null;
  }

  bool get isOk => mounted && totalBytes > 0;

  int get usedPercent {
    if (reportedUsedPercent != null) return reportedUsedPercent!.clamp(0, 100);
    if (totalBytes <= 0) return 0;
    return ((usedBytes * 100) / totalBytes).round().clamp(0, 100);
  }

  double get usedFraction => usedPercent / 100;

  @override
  List<Object?> get props => [
        status,
        mounted,
        cardDetected,
        cardType,
        totalBytes,
        usedBytes,
        freeBytes,
        reportedUsedPercent,
      ];
}
