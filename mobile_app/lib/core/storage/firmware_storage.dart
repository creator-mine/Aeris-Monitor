import 'package:hive/hive.dart';
import '../../models/firmware_version.dart';

class FirmwareStorage {
  static const String _boxName = 'firmware_versions';
  late Box<FirmwareVersion> _box;

  Future<void> init() async {
    _box = await Hive.openBox<FirmwareVersion>(_boxName);
  }

  List<FirmwareVersion> getAll() {
    return _box.values.toList();
  }

  List<FirmwareVersion> getByDeviceType(String deviceType) {
    return _box.values
        .where((v) => v.deviceType == deviceType)
        .toList();
  }

  FirmwareVersion? getById(String id) {
    for (final v in _box.values) {
      if (v.id == id) return v;
    }
    return null;
  }

  FirmwareVersion? getLatestByDevice(String deviceType) {
    final versions = getByDeviceType(deviceType);
    if (versions.isEmpty) return null;
    versions.sort((a, b) => b.buildDate.compareTo(a.buildDate));
    return versions.first;
  }

  String getNextVersion(String deviceType, {String bumpType = 'patch'}) {
    final latest = getLatestByDevice(deviceType);
    if (latest == null) return '1.0.0';

    final parts = latest.version.split('.');
    if (parts.length != 3) return '1.0.0';

    int major = int.tryParse(parts[0]) ?? 1;
    int minor = int.tryParse(parts[1]) ?? 0;
    int patch = int.tryParse(parts[2]) ?? 0;

    switch (bumpType) {
      case 'major':
        major++;
        minor = 0;
        patch = 0;
        break;
      case 'minor':
        minor++;
        patch = 0;
        break;
      case 'patch':
      default:
        patch++;
        break;
    }

    return '$major.$minor.$patch';
  }

  Future<void> save(FirmwareVersion version) async {
    await _box.put(version.id, version);
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  Future<void> clear() async {
    await _box.clear();
  }

  int get count => _box.length;
}
