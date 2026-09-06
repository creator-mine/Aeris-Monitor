import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../models/firmware_version.dart';
import '../../../core/api/firmware_service.dart';
import '../../../core/storage/firmware_storage.dart';

class FirmwareProvider extends ChangeNotifier {
  final FirmwareService _service = FirmwareService();
  final FirmwareStorage _storage = FirmwareStorage();
  static const _uuid = Uuid();

  List<FirmwareVersion> _versions = [];
  String? _selectedPort;
  String _selectedDeviceType = 'esp32-c3';
  String? _sourcePath;
  bool _isBuilding = false;
  bool _isUploading = false;
  List<String> _buildLogs = [];
  bool _platformioAvailable = false;
  List<String> _availablePorts = [];
  List<PortInfo> _portInfos = [];
  String? _currentHash;
  bool _hasUpdates = false;
  Map<String, String> _currentFileHashes = <String, String>{};
  Map<String, dynamic> _projectInfo = <String, dynamic>{};
  Map<String, dynamic> _firmwareBinInfo = <String, dynamic>{};
  Map<String, dynamic> _gitInfo = <String, dynamic>{};
  String? _pendingVersion;
  DateTime? _buildStartedAt;
  Duration? _lastBuildDuration;
  List<PreflightItem> _preflightItems = <PreflightItem>[];
  bool _isPreflightChecking = false;
  bool _isDetectingChip = false;
  String? _detectedChip;
  String? _detectChipError;
  StreamSubscription<String>? _buildSubscription;

  List<FirmwareVersion> get versions => _versions;
  String? get selectedPort => _selectedPort;
  String get selectedDeviceType => _selectedDeviceType;
  String? get sourcePath => _sourcePath;
  bool get isBuilding => _isBuilding;
  bool get isUploading => _isUploading;
  List<String> get buildLogs => _buildLogs;
  bool get platformioAvailable => _platformioAvailable;
  List<String> get availablePorts => _availablePorts;
  List<PortInfo> get portInfos => _portInfos;

  PortInfo? portInfoFor(String port) {
    for (final info in _portInfos) {
      if (info.port == port) return info;
    }
    return null;
  }
  String? get currentHash => _currentHash;
  bool get hasUpdates => _hasUpdates;
  Map<String, dynamic> get projectInfo => _projectInfo;
  Map<String, dynamic> get firmwareBinInfo => _firmwareBinInfo;
  FirmwareVersion? get latestVersion =>
      versionsForDevice.isNotEmpty ? versionsForDevice.first : null;
  List<FileChangeInfo> get fileChanges => _computeFileChanges();
  Map<String, dynamic> get gitInfo => _gitInfo;
  String? get pendingVersion => _pendingVersion;
  DateTime? get buildStartedAt => _buildStartedAt;
  Duration? get lastBuildDuration => _lastBuildDuration;
  List<PreflightItem> get preflightItems => _preflightItems;
  bool get isPreflightChecking => _isPreflightChecking;
  bool get isDetectingChip => _isDetectingChip;
  String? get detectedChip => _detectedChip;
  String? get detectChipError => _detectChipError;
  String get expectedChipName =>
      _selectedDeviceType.toLowerCase().contains('c6') ? 'ESP32-C6' : 'ESP32-C3';
  String get autoNextVersion => _storage.getNextVersion(_selectedDeviceType);

  static final RegExp _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  /// Sets a manual version for the next build. Empty/invalid input clears it.
  /// Returns whether the provided value was accepted.
  bool setPendingVersion(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      _pendingVersion = null;
      notifyListeners();
      return true;
    }
    if (!_versionPattern.hasMatch(v)) return false;
    _pendingVersion = v;
    notifyListeners();
    return true;
  }

  void clearPendingVersion() {
    _pendingVersion = null;
    notifyListeners();
  }
  FirmwareVersion? previousVersionOf(FirmwareVersion version) {
    final versions = versionsForDevice;
    final index = versions.indexWhere((v) => v.id == version.id);
    if (index < 0 || index >= versions.length - 1) return null;
    return versions[index + 1];
  }

  List<FileChangeInfo> _computeFileChanges() {
    final latestHashes = latestVersion?.fileHashes ?? const <String, String>{};
    final changes = <FileChangeInfo>[];

    for (final entry in _currentFileHashes.entries) {
      if (!latestHashes.containsKey(entry.key)) {
        changes.add(FileChangeInfo(entry.key, FileChangeKind.added));
      } else if (latestHashes[entry.key] != entry.value) {
        changes.add(FileChangeInfo(entry.key, FileChangeKind.modified));
      }
    }
    for (final key in latestHashes.keys) {
      if (!_currentFileHashes.containsKey(key)) {
        changes.add(FileChangeInfo(key, FileChangeKind.removed));
      }
    }

    changes.sort((a, b) => a.path.compareTo(b.path));
    return changes;
  }

  bool get canBuild => _sourcePath != null && _platformioAvailable;
  bool get canUpload => canBuild && _selectedPort != null && !_isBuilding && !_isUploading;

  List<FirmwareVersion> get versionsForDevice =>
      _versions.where((v) => v.deviceType == _selectedDeviceType).toList()
        ..sort((a, b) => b.buildDate.compareTo(a.buildDate));

  Future<void> init() async {
    await _storage.init();
    _versions = _storage.getAll();
    _platformioAvailable = await _service.isPlatformIOAvailable();

    final prefs = await SharedPreferences.getInstance();
    _selectedPort = prefs.getString('firmware_last_port');
    _selectedDeviceType = prefs.getString('firmware_last_device') ?? 'esp32-c3';
    _sourcePath = prefs.getString('firmware_last_path');

    if (_sourcePath != null) {
      await checkForUpdates();
    }

    await refreshPorts();
    await loadProjectInfo();
    notifyListeners();
  }

  Future<void> refreshPorts() async {
    final infos = await _service.getAvailablePortsWithInfo();
    _portInfos = infos;
    _availablePorts = infos.map((i) => i.port).toList();
    if (_selectedPort != null && !_availablePorts.contains(_selectedPort)) {
      _selectedPort = _availablePorts.isNotEmpty ? _availablePorts.first : null;
    }
    notifyListeners();
  }

  Future<void> selectFolder(String path) async {
    _sourcePath = path;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('firmware_last_path', path);

    await checkForUpdates();
    await loadProjectInfo();
    notifyListeners();
  }

  Future<void> selectPort(String port) async {
    _selectedPort = port;
    _detectedChip = null;
    _detectChipError = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('firmware_last_port', port);

    notifyListeners();
  }

  Future<void> detectChip() async {
    if (_isDetectingChip || _selectedPort == null) return;

    _isDetectingChip = true;
    _detectedChip = null;
    _detectChipError = null;
    notifyListeners();

    final result = await _service.detectChipOnPort(_selectedPort!);

    _isDetectingChip = false;
    if (result.success && result.chip != null) {
      _detectedChip = result.chip;
    } else {
      _detectChipError = result.message;
    }
    notifyListeners();
  }

  Future<void> selectDeviceType(String type) async {
    _selectedDeviceType = type;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('firmware_last_device', type);

    if (_sourcePath != null) {
      await checkForUpdates();
      await loadProjectInfo();
    }

    notifyListeners();
  }

  Future<void> loadProjectInfo() async {
    if (_sourcePath == null) {
      _projectInfo = <String, dynamic>{};
      _firmwareBinInfo = <String, dynamic>{};
      notifyListeners();
      return;
    }

    try {
      _projectInfo = await _service.getProjectInfo(_sourcePath!, _selectedDeviceType);
    } catch (_) {
      _projectInfo = <String, dynamic>{};
    }

    try {
      _firmwareBinInfo = await _service.getFirmwareBinInfo(_sourcePath!, _selectedDeviceType);
    } catch (_) {
      _firmwareBinInfo = <String, dynamic>{};
    }

    _gitInfo = await _service.getGitInfo(_sourcePath!);

    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    if (_sourcePath == null) return;

    try {
      _currentHash = await _service.calculateSourceHash(_sourcePath!);
      _currentFileHashes = await _service.calculateSourceFileHashes(_sourcePath!);
      final latest = _storage.getLatestByDevice(_selectedDeviceType);

      if (latest != null && latest.buildHash != null) {
        _hasUpdates = _currentHash != latest.buildHash;
      } else {
        _hasUpdates = true;
      }
    } catch (e) {
      _currentFileHashes = <String, String>{};
      _hasUpdates = true;
    }

    notifyListeners();
  }

  Future<void> build() async {
    if (!canBuild || _sourcePath == null) return;

    _isBuilding = true;
    _buildStartedAt = DateTime.now();
    _lastBuildDuration = null;
    _buildLogs = [
      'Start build for $_selectedDeviceType...',
      'Path: $_sourcePath',
      if (_pendingVersion != null) 'Version: v${_pendingVersion}',
      if (_gitInfo['isRepo'] == true)
        'Git: ${_gitInfo['branch']} @ ${_gitInfo['commit']}${_gitInfo['message'].isNotEmpty ? ' (${_gitInfo['message']})' : ''}',
      '',
    ];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = _service.buildFirmware(_sourcePath!, _selectedDeviceType);

    _buildSubscription = stream.listen(
      (line) {
        _buildLogs.add(line);
        notifyListeners();
      },
      onDone: () async {
        _isBuilding = false;
        _lastBuildDuration = _buildStartedAt != null
            ? DateTime.now().difference(_buildStartedAt!)
            : null;
        _buildStartedAt = null;

        if (_buildLogs.any((l) => l.contains('[SUCCESS]'))) {
          var snapshot = <String, dynamic>{};
          Map<String, String> fileHashesMap = <String, String>{};
          try {
            snapshot = await _service.captureConfigSnapshot(_sourcePath!);
          } catch (_) {}
          try {
            fileHashesMap = await _service.calculateSourceFileHashes(_sourcePath!);
          } catch (_) {}

          final version = FirmwareVersion(
            id: _uuid.v4(),
            version: _pendingVersion ?? _storage.getNextVersion(_selectedDeviceType),
            deviceType: _selectedDeviceType,
            sourcePath: _sourcePath!,
            buildDate: DateTime.now(),
            buildHash: _currentHash,
            isBuilt: true,
            firmwarePath: _service.findFirmwareBin(_sourcePath!, _selectedDeviceType),
            configSnapshot: snapshot,
            fileHashes: fileHashesMap,
          );
          _pendingVersion = null;

          await _storage.save(version);
          _versions = _storage.getAll();
          _hasUpdates = false;
          await loadProjectInfo();
        }

        notifyListeners();
      },
    );
  }

  Future<void> upload() async {
    if (!canUpload || _sourcePath == null || _selectedPort == null) return;

    _isUploading = true;
    _buildLogs = ['Uploading to $_selectedPort...', ''];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = _service.uploadFirmware(
      _sourcePath!,
      _selectedDeviceType,
      _selectedPort!,
    );

    _buildSubscription = stream.listen(
      (line) {
        _buildLogs.add(line);
        notifyListeners();
      },
      onDone: () async {
        _isUploading = false;

        if (_buildLogs.any((l) => l.contains('[SUCCESS]'))) {
          final latest = _storage.getLatestByDevice(_selectedDeviceType);
          if (latest != null) {
            latest.lastUploadPort = _selectedPort;
            latest.lastUploadDate = DateTime.now();
            await _storage.save(latest);
            _versions = _storage.getAll();
          }
        }

        notifyListeners();
      },
    );
  }

  Future<void> uploadVersion(FirmwareVersion version) async {
    if (_selectedPort == null) return;

    _isUploading = true;
    _buildLogs = ['Uploading version ${version.version} to $_selectedPort...', ''];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = _service.uploadFirmware(
      version.sourcePath,
      version.pioEnvironment,
      _selectedPort!,
    );

    _buildSubscription = stream.listen(
      (line) {
        _buildLogs.add(line);
        notifyListeners();
      },
      onDone: () async {
        _isUploading = false;

        if (_buildLogs.any((l) => l.contains('[SUCCESS]'))) {
          version.lastUploadPort = _selectedPort;
          version.lastUploadDate = DateTime.now();
          await _storage.save(version);
          _versions = _storage.getAll();
        }

        notifyListeners();
      },
    );
  }

  Future<void> deleteVersion(String id) async {
    await _storage.delete(id);
    _versions = _storage.getAll();
    notifyListeners();
  }

  void cancelBuild() {
    _buildSubscription?.cancel();
    _buildSubscription = null;
    _service.cancelActiveProcess();
    _isBuilding = false;
    _isUploading = false;
    _buildLogs.add('[CANCELLED] Build cancelled');
    notifyListeners();
  }

  Future<void> runPreflight() async {
    if (_isPreflightChecking) return;

    _isPreflightChecking = true;
    _preflightItems = <PreflightItem>[];
    notifyListeners();

    final items = <PreflightItem>[];

    final cliVersion = await _service.getPlatformIOVersion();
    items.add(PreflightItem(
      'PlatformIO CLI',
      ok: cliVersion != null,
      detail: cliVersion ?? 'не найден',
    ));

    final iniOk = _projectInfo.isNotEmpty && !_projectInfo.containsKey('error');
    items.add(PreflightItem(
      'platformio.ini',
      ok: iniOk,
      detail: iniOk ? 'найден' : 'не найден',
    ));

    final envs = (_projectInfo['environments'] as List?) ?? <dynamic>[];
    final envOk = envs.contains(_selectedDeviceType);
    items.add(PreflightItem(
      'Среда $_selectedDeviceType',
      ok: envOk,
      detail: envOk ? 'определена' : 'не определена',
    ));

    if (iniOk && _sourcePath != null) {
      final pkgs = await _service.platformioPkgList(_sourcePath!, _selectedDeviceType);
      final platformSpec = _projectInfo['platform']?.toString() ?? '';
      final baseName = platformSpec.split('@').first.trim();

      final platformPkgs = pkgs.where((p) => p['type'] == 'platform').toList();
      final frameworkPkgs = pkgs.where((p) => p['type'] == 'framework').toList();

      final platformMatch = baseName.isEmpty
          ? platformPkgs.isNotEmpty
          : platformPkgs.any((p) => p['name']?.toString().contains(baseName) == true || baseName.isEmpty);
      items.add(PreflightItem(
        'Платформа',
        ok: platformPkgs.isNotEmpty && (baseName.isEmpty || platformMatch),
        detail: platformPkgs.isNotEmpty
            ? platformPkgs.map((p) => '${p['name']}@${p['version']}').join(', ')
            : baseName.isEmpty ? 'не установлена' : '$baseName не установлена',
      ));

      items.add(PreflightItem(
        'Фреймворк',
        ok: frameworkPkgs.isNotEmpty,
        detail: frameworkPkgs.isNotEmpty
            ? frameworkPkgs.map((p) => '${p['name']}@${p['version']}').join(', ')
            : 'не установлен',
      ));
    }

    final binOk = _firmwareBinInfo['exists'] == true;
    items.add(PreflightItem(
      'firmware.bin',
      ok: binOk,
      detail: binOk ? 'собран' : 'не собран',
    ));

    items.add(PreflightItem(
      'Порт (устройство)',
      ok: _selectedPort != null,
      detail: _selectedPort ?? 'не выбран',
    ));

    _preflightItems = items;
    _isPreflightChecking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _buildSubscription?.cancel();
    _service.cancelActiveProcess();
    super.dispose();
  }
}

enum FileChangeKind { added, modified, removed }

class FileChangeInfo {
  final String path;
  final FileChangeKind kind;

  const FileChangeInfo(this.path, this.kind);

  String get label => switch (kind) {
        FileChangeKind.added => 'добавлен',
        FileChangeKind.modified => 'изменён',
        FileChangeKind.removed => 'удалён',
      };
}

class PreflightItem {
  final String title;
  final bool ok;
  final String detail;

  const PreflightItem(this.title, {required this.ok, required this.detail});
}
