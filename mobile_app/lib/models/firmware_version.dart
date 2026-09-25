import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

part 'firmware_version.g.dart';

@HiveType(typeId: 10)
class FirmwareVersion extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String version;

  @HiveField(2)
  String deviceType;

  @HiveField(3)
  String sourcePath;

  @HiveField(4)
  DateTime buildDate;

  @HiveField(5)
  String? buildHash;

  @HiveField(6)
  bool isBuilt;

  @HiveField(7)
  String? firmwarePath;

  @HiveField(8)
  String? lastUploadPort;

  @HiveField(9)
  DateTime? lastUploadDate;

  @HiveField(10)
  Map<String, dynamic>? configSnapshot;

  @HiveField(11)
  Map<String, String>? fileHashes;

  FirmwareVersion({
    required this.id,
    required this.version,
    required this.deviceType,
    required this.sourcePath,
    required this.buildDate,
    this.buildHash,
    this.isBuilt = false,
    this.firmwarePath,
    this.lastUploadPort,
    this.lastUploadDate,
    this.configSnapshot,
    this.fileHashes,
  });

  static final DateFormat _dateFmt = DateFormat('dd.MM.yyyy HH:mm');

  String get deviceLabel {
    switch (deviceType) {
      case 'esp32-c3':
        return 'ESP32-C3 Main Controller';
      case 'esp32-c6':
        return 'ESP32-C6 Sensor Module';
      case 'esp32-s3':
        return 'ESP32-S3 Main Controller';
      default:
        return deviceType.toUpperCase();
    }
  }

  String get pioEnvironment {
    switch (deviceType) {
      case 'esp32-c3':
        return 'esp32-c3';
      case 'esp32-c6':
        return 'esp32-c6';
      case 'esp32-s3':
        return 'esp32-s3';
      default:
        return deviceType;
    }
  }

  String get buildDateFormatted => _dateFmt.format(buildDate);

  String get lastUploadFormatted {
    if (lastUploadDate == null) return '—';
    return _dateFmt.format(lastUploadDate!);
  }

  FirmwareVersion copyWith({
    String? version,
    String? deviceType,
    String? sourcePath,
    DateTime? buildDate,
    String? buildHash,
    bool? isBuilt,
    String? firmwarePath,
    String? lastUploadPort,
    DateTime? lastUploadDate,
    Map<String, dynamic>? configSnapshot,
    Map<String, String>? fileHashes,
  }) {
    return FirmwareVersion(
      id: id,
      version: version ?? this.version,
      deviceType: deviceType ?? this.deviceType,
      sourcePath: sourcePath ?? this.sourcePath,
      buildDate: buildDate ?? this.buildDate,
      buildHash: buildHash ?? this.buildHash,
      isBuilt: isBuilt ?? this.isBuilt,
      firmwarePath: firmwarePath ?? this.firmwarePath,
      lastUploadPort: lastUploadPort ?? this.lastUploadPort,
      lastUploadDate: lastUploadDate ?? this.lastUploadDate,
      configSnapshot: configSnapshot ?? this.configSnapshot,
      fileHashes: fileHashes ?? this.fileHashes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirmwareVersion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version &&
          buildDate == other.buildDate &&
          isBuilt == other.isBuilt &&
          deviceType == other.deviceType;

  @override
  int get hashCode => Object.hash(id, version, buildDate, isBuilt, deviceType);
}
