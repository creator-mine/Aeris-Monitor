import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../models/firmware_version.dart';
import '../../../models/firmware_manifest.dart';
import '../../../models/staged_firmware.dart';
import '../../../core/api/firmware_fetcher.dart';
import '../../../core/api/firmware_service.dart';
import '../../../core/api/ota_api.dart';
import '../../../core/storage/firmware_storage.dart';
import '../../../core/utils/firmware_file.dart';
import '../../../core/utils/version.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/helpers/chip_helper.dart';

class FirmwareProvider extends ChangeNotifier {
  final FirmwareService _service;
  final FirmwareFetcher _fetcher;
  final FirmwareStorage _storage = FirmwareStorage();
  String? _otaBaseUrl;
  static const _uuid = Uuid();

  FirmwareProvider({String? otaBaseUrl, FirmwareFetcher? fetcher})
      : _otaBaseUrl = otaBaseUrl,
        _fetcher = fetcher ?? FirmwareFetcher(),
        _service = FirmwareService();

  /// OTA host used for manifest checks. Updatable at runtime so the user can
  /// point the app at a self-hosted server without restarting.
  void setOtaBaseUrl(String? url) {
    _otaBaseUrl = url;
  }

  List<FirmwareVersion> _versions = [];
  String? _selectedPort;
  String _selectedDeviceType = 'esp32-c3';
  String? _sourcePath;
  bool _isBuilding = false;
  bool _isUploading = false;
  bool _isInstallingPlatformio = false;
  List<String> _buildLogs = [];
  bool _platformioAvailable = false;
  List<String> _availablePorts = [];
  List<PortInfo> _portInfos = [];
  String? _currentHash;
  bool _hasUpdates = false;
  String? _updateCheckError;
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

  StagedFirmware? _stagedFirmware;
  bool _isStaging = false;
  double? _downloadProgress;
  String? _stageError;
  CancelToken? _downloadCancel;

  FirmwareManifest? _serverManifest;
  bool _isCheckingServer = false;
  bool _manifestCheckQueued = false;
  String? _serverCheckError;
  String? _localVersion;

  List<FirmwareVersion> get versions => _versions;
  String? get selectedPort => _selectedPort;
  String get selectedDeviceType => _selectedDeviceType;
  String? get sourcePath => _sourcePath;
  bool get isBuilding => _isBuilding;
  bool get isUploading => _isUploading;
  bool get isInstallingPlatformio => _isInstallingPlatformio;
  StagedFirmware? get stagedFirmware => _stagedFirmware;
  bool get isStaging => _isStaging;
  double? get downloadProgress => _downloadProgress;
  String? get stageError => _stageError;
  bool get canStagePublished =>
      _serverManifest != null && !_isStaging && !_isUploading;
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
  String? get updateCheckError => _updateCheckError;
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
  String get expectedChipName => expectedChipNameFor(_selectedDeviceType);
  String get autoNextVersion {
    // Prefer the project's own FIRMWARE_VERSION (include/config.h) so builds
    // are labelled with the real version instead of a history-based bump.
    final config = _localVersion;
    if (config != null && config.isNotEmpty) return config;
    return _storage.getNextVersion(_selectedDeviceType);
  }

  FirmwareManifest? get serverManifest => _serverManifest;
  bool get isCheckingServer => _isCheckingServer;
  String? get serverCheckError => _serverCheckError;
  String? get localVersion => _localVersion;
  String? get latestPublishedVersion => _serverManifest?.version;
  bool get hasServerManifest => _serverManifest != null;

  /// Real freshness of the local project source vs the published firmware.
  FirmwareFreshness get freshness =>
      firmwareFreshness(_localVersion, _serverManifest?.version);

  static final RegExp _versionPattern = RegExp(r'^\d+\.\d+\.\d+$');

  /// Extracts the semver (e.g. "1.2.2") from an external .bin file name like
  /// "aeris-esp32c3-v1.2.2.bin". Returns null when absent.
  static String? versionFromFilename(String name) =>
      firmwareVersionFromName(name);

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

  bool get canBuild =>
      _sourcePath != null && _platformioAvailable && !_isStaging;
  bool get canUpload =>
      canBuild &&
      _selectedPort != null &&
      !_isBuilding &&
      !_isUploading &&
      !_isStaging;
  bool get canFlashStaged =>
      _stagedFirmware != null &&
      _selectedPort != null &&
      !_isBuilding &&
      !_isUploading &&
      !_isStaging;

  List<FirmwareVersion> get versionsForDevice =>
      _versions.where((v) => v.deviceType == _selectedDeviceType).toList()
        ..sort((a, b) => b.buildDate.compareTo(a.buildDate));

  Future<void> init() async {
    await _storage.init();
    _versions = _storage.getAll();

    final prefs = await SharedPreferences.getInstance();
    _selectedPort = prefs.getString('firmware_last_port');
    _selectedDeviceType = prefs.getString('firmware_last_device') ?? 'esp32-c3';
    _sourcePath = prefs.getString('firmware_last_path');

    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      _platformioAvailable = await _service.isPlatformIOAvailable();
      await checkForUpdates();
      await refreshPorts();
      await loadProjectInfo();
    }

    await fetchServerManifest();
    notifyListeners();
  }

  Future<void> refreshPorts() async {
    if (kIsWeb) return;
    final infos = await _service.getAvailablePortsWithInfo();
    _portInfos = infos;
    _availablePorts = infos.map((i) => i.port).toList();
    if (_selectedPort != null && !_availablePorts.contains(_selectedPort)) {
      _selectedPort = _availablePorts.isNotEmpty ? _availablePorts.first : null;
    }
    notifyListeners();
  }

  Future<void> selectFolder(String path) async {
    if (kIsWeb) return;
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
    if (kIsWeb || _isDetectingChip || _selectedPort == null) return;

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
    if (type == _selectedDeviceType) return;
    _selectedDeviceType = type;
    _serverManifest = null;
    _serverCheckError = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('firmware_last_device', type);

    // The published manifest is per device type (ESP32/C3/C6/S3 have their own
    // files), so refresh it immediately instead of showing the old one.
    await fetchServerManifest();

    if (_sourcePath != null) {
      await checkForUpdates();
      await loadProjectInfo();
    }

    notifyListeners();
  }

  Future<void> loadProjectInfo() async {
    if (_sourcePath == null || kIsWeb) {
      _projectInfo = <String, dynamic>{};
      _firmwareBinInfo = <String, dynamic>{};
      notifyListeners();
      return;
    }

    try {
      _projectInfo =
          await _service.getProjectInfo(_sourcePath!, _selectedDeviceType);
    } catch (_) {
      _projectInfo = <String, dynamic>{};
    }

    try {
      _firmwareBinInfo =
          await _service.getFirmwareBinInfo(_sourcePath!, _selectedDeviceType);
    } catch (_) {
      _firmwareBinInfo = <String, dynamic>{};
    }

    _gitInfo = await _service.getGitInfo(_sourcePath!);
    await _loadLocalVersion();

    notifyListeners();
  }

  /// Fetches the real published firmware version from the OTA site
  /// (/fw/version.json). No stubs: failures surface as a check error.
  Future<void> fetchServerManifest() async {
    if (_isCheckingServer) {
      // A device-type/host switch happened mid-request: re-run afterwards.
      _manifestCheckQueued = true;
      return;
    }
    _isCheckingServer = true;
    _serverCheckError = null;
    final requestedType = _selectedDeviceType;
    notifyListeners();

    try {
      final manifest = await _service.fetchOtaManifest(
        deviceType: requestedType,
        baseUrl: _otaBaseUrl,
      );
      // Ignore a response that belongs to a previously selected device type.
      if (requestedType != _selectedDeviceType) {
        _manifestCheckQueued = true;
        return;
      }
      _serverManifest = manifest;
      if (manifest == null) {
        _serverCheckError = 'Не удалось получить данные с сайта '
            '${_otaBaseUrl ?? AppConfig.apiBaseUrl} '
            '(${OtaApi.manifestPathFor(requestedType)}). '
            'Проверьте интернет или опубликуйте прошивку через deploy/fw.ps1.';
      }
    } catch (e) {
      if (requestedType == _selectedDeviceType) {
        _serverCheckError = 'Ошибка проверки обновлений: $e';
      }
    } finally {
      _isCheckingServer = false;
      notifyListeners();
      if (_manifestCheckQueued) {
        _manifestCheckQueued = false;
        unawaited(fetchServerManifest());
      }
    }
  }

  /// Checks whether the local source changed compared with the last saved
  /// build of the selected device (i.e. whether a rebuild is needed).
  /// This is separate from the published-version check above.
  Future<void> checkForUpdates() async {
    if (_sourcePath == null || kIsWeb) return;

    _updateCheckError = null;
    try {
      _currentHash = await _service.calculateSourceHash(_sourcePath!);
      _currentFileHashes =
          await _service.calculateSourceFileHashes(_sourcePath!);
      final latest = _storage.getLatestByDevice(_selectedDeviceType);

      if (latest != null && latest.buildHash != null) {
        _hasUpdates = _currentHash != latest.buildHash;
      } else if (latest != null) {
        _hasUpdates = true; // saved build has no hash — can't verify
      } else {
        _hasUpdates = true; // nothing built for this device yet
      }
    } catch (e) {
      _currentFileHashes = <String, String>{};
      _updateCheckError = 'Не удалось проверить исходники: $e';
      _hasUpdates = false;
    }

    await _loadLocalVersion();
    notifyListeners();
  }

  Future<void> _loadLocalVersion() async {
    if (_sourcePath == null) {
      _localVersion = null;
      return;
    }
    try {
      _localVersion = await _service.getFirmwareVersionFromConfig(_sourcePath!);
    } catch (_) {
      _localVersion = null;
    }
  }

  Future<void> build() async {
    if (!canBuild || _sourcePath == null || _isInstallingPlatformio || kIsWeb) {
      return;
    }

    // Capture everything the build is based on: the user can switch device
    // type or folder while it runs, and the saved record must still describe
    // the artifact that was actually produced.
    final deviceType = _selectedDeviceType;
    final sourcePath = _sourcePath!;
    final pendingVersion = _pendingVersion;
    final autoVersion = autoNextVersion;
    final buildHash = _currentHash;

    _isBuilding = true;
    _buildStartedAt = DateTime.now();
    _lastBuildDuration = null;
    _buildLogs = [
      'Start build for $deviceType...',
      'Path: $sourcePath',
      if (pendingVersion != null) 'Version: v$pendingVersion',
      if (_gitInfo['isRepo'] == true)
        'Git: ${_gitInfo['branch']} @ ${_gitInfo['commit']}${_gitInfo['message'].isNotEmpty ? ' (${_gitInfo['message']})' : ''}',
      '',
    ];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = _service.buildFirmware(sourcePath, deviceType);

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
            snapshot = await _service.captureConfigSnapshot(sourcePath);
          } catch (_) {}
          try {
            fileHashesMap =
                await _service.calculateSourceFileHashes(sourcePath);
          } catch (_) {}

          final version = FirmwareVersion(
            id: _uuid.v4(),
            version: pendingVersion ?? autoVersion,
            deviceType: deviceType,
            sourcePath: sourcePath,
            buildDate: DateTime.now(),
            buildHash: buildHash,
            isBuilt: true,
            firmwarePath: _service.findFirmwareBin(sourcePath, deviceType),
            configSnapshot: snapshot,
            fileHashes: fileHashesMap,
          );
          if (_pendingVersion == pendingVersion) _pendingVersion = null;

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
    if (!canUpload ||
        _sourcePath == null ||
        _selectedPort == null ||
        _isInstallingPlatformio ||
        kIsWeb) {
      return;
    }

    final deviceType = _selectedDeviceType;
    final sourcePath = _sourcePath!;
    final port = _selectedPort!;

    _isUploading = true;
    _buildLogs = ['Uploading to $port...', ''];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = _service.uploadFirmware(
      sourcePath,
      deviceType,
      port,
    );

    _buildSubscription = stream.listen(
      (line) {
        _buildLogs.add(line);
        notifyListeners();
      },
      onDone: () async {
        _isUploading = false;

        if (_buildLogs.any((l) => l.contains('[SUCCESS]'))) {
          final latest = _storage.getLatestByDevice(deviceType);
          if (latest != null) {
            latest.lastUploadPort = port;
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
    if (_selectedPort == null || _isInstallingPlatformio || kIsWeb) return;
    if (!version.isBuilt && version.firmwarePath == null) return;

    _isUploading = true;
    _buildLogs = [
      'Uploading ${version.isBuilt ? 'build' : 'firmware'} '
          'v${version.version} to $_selectedPort...',
      '',
    ];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = version.isBuilt
        ? _service.uploadFirmware(
            version.sourcePath,
            version.pioEnvironment,
            _selectedPort!,
          )
        : _service.flashBinary(
            version.firmwarePath!,
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

  /// Copies a picked `.bin` into app storage and prepares it for flashing.
  Future<void> stageLocalFirmware(String sourcePath) async {
    if (kIsWeb || _isStaging) return;
    _isStaging = true;
    _downloadProgress = null;
    _stageError = null;
    _buildLogs = ['Подготовка файла прошивки...', ''];
    notifyListeners();

    try {
      final staged = await _fetcher.stageLocalFile(
        sourcePath,
        preferredDeviceType: _selectedDeviceType,
      );
      await _commitStaged(staged);
      _buildLogs.add(
        '[OK] ${staged.fileName} · ${staged.sizeLabel} · SHA-256 ${staged.shortHash}',
      );
    } on FirmwareFetchException catch (e) {
      _stageError = e.message;
      _buildLogs.add('[ERROR] ${e.message}');
    } catch (e) {
      _stageError = 'Не удалось подготовить прошивку: $e';
      _buildLogs.add('[ERROR] $_stageError');
    } finally {
      _isStaging = false;
      notifyListeners();
    }
  }

  /// Downloads a `.bin` from a GitHub link (file, raw, release) or any HTTPS
  /// URL and stages it for flashing.
  Future<void> stageFromUrl(
    String url, {
    String? version,
    String? expectedSha256,
    int? expectedBytes,
  }) async {
    if (kIsWeb || _isStaging) return;
    _isStaging = true;
    _downloadProgress = 0;
    _stageError = null;
    _buildLogs = ['Скачивание прошивки...', url, ''];
    notifyListeners();

    final cancel = CancelToken();
    _downloadCancel = cancel;
    var lastProgressNotify = 0;

    try {
      final staged = await _fetcher.downloadFromUrl(
        url,
        preferredDeviceType: _selectedDeviceType,
        version: version,
        expectedSha256: expectedSha256,
        expectedBytes: expectedBytes,
        cancelToken: cancel,
        onProgress: (received, total) {
          _downloadProgress = total > 0 ? received / total : null;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastProgressNotify > 100) {
            lastProgressNotify = now;
            notifyListeners();
          }
        },
      );
      await _commitStaged(staged);
      _buildLogs.add(
        '[OK] ${staged.fileName} · ${staged.sizeLabel} · SHA-256 ${staged.shortHash}',
      );
    } on FirmwareFetchException catch (e) {
      _stageError = e.message;
      _buildLogs.add('[ERROR] ${e.message}');
    } catch (e) {
      _stageError = 'Не удалось скачать прошивку: $e';
      _buildLogs.add('[ERROR] $_stageError');
    } finally {
      _downloadCancel = null;
      _isStaging = false;
      _downloadProgress = null;
      notifyListeners();
    }
  }

  /// Downloads the firmware currently published in the OTA manifest and
  /// verifies its size and SHA-256 before staging.
  Future<void> stagePublishedFirmware() async {
    final manifest = _serverManifest;
    if (manifest == null) {
      _stageError = 'Опубликованная версия ещё не получена';
      notifyListeners();
      return;
    }
    final base = (_otaBaseUrl ?? AppConfig.apiBaseUrl)
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    final file = manifest.file.isNotEmpty
        ? manifest.file
        : OtaApi.binaryPathFor(_selectedDeviceType);
    await stageFromUrl(
      '$base/fw/$file',
      version: manifest.version,
      expectedSha256: manifest.sha256,
      expectedBytes: manifest.sizeBytes,
    );
  }

  void cancelStaging() {
    _downloadCancel?.cancel('Отменено пользователем');
  }

  /// Clears the pending image and removes its private copy.
  Future<void> clearStagedFirmware() async {
    await _replaceStaged(null);
    _stageError = null;
    notifyListeners();
  }

  Future<void> _commitStaged(StagedFirmware staged) async {
    final old = _stagedFirmware;
    _stagedFirmware = staged;
    if (old != null && old.path != staged.path) {
      await old.deleteFile();
    }
  }

  Future<void> _replaceStaged(StagedFirmware? next) async {
    final old = _stagedFirmware;
    _stagedFirmware = next;
    if (old != null && old.path != next?.path) {
      await old.deleteFile();
    }
  }

  /// Flashes the staged image with esptool. No project folder or PlatformIO
  /// build is needed — only esptool itself (installed with PlatformIO).
  Future<void> flashStaged() async {
    final staged = _stagedFirmware;
    final port = _selectedPort;
    if (staged == null || port == null || !canFlashStaged) return;

    _isUploading = true;
    _stageError = null;
    _buildLogs = [
      'Загрузка ${staged.fileName} на $port...',
      '',
    ];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = _service.flashBinary(staged.path, port);
    _buildSubscription = stream.listen(
      (line) {
        _buildLogs.add(line);
        notifyListeners();
      },
      onDone: () async {
        _isUploading = false;

        if (_buildLogs.any((l) => l.contains('[SUCCESS]'))) {
          final record = FirmwareVersion(
            id: _uuid.v4(),
            version:
                staged.version ?? _storage.getNextVersion(staged.deviceType),
            deviceType: staged.deviceType,
            sourcePath: staged.sourceUrl ?? p.dirname(staged.path),
            buildDate: DateTime.now(),
            buildHash: staged.sha256,
            isBuilt: false,
            firmwarePath: staged.path,
            lastUploadPort: port,
            lastUploadDate: DateTime.now(),
          );
          await _storage.save(record);
          _versions = _storage.getAll();
          _stagedFirmware = null;
        } else {
          final errors = _buildLogs.where((l) => l.contains('[ERROR]'));
          if (errors.isNotEmpty) {
            _stageError = errors.last.replaceFirst('[ERROR]', '').trim();
          }
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
    _isInstallingPlatformio = false;
    _buildLogs.add('[CANCELLED] Build cancelled');
    notifyListeners();
  }

  /// Installs PlatformIO Core via pip and, on success, refreshes the
  /// availability flag and serial ports so building becomes possible.
  Future<void> installPlatformIO() async {
    if (_isInstallingPlatformio || _isBuilding || _isUploading || kIsWeb) {
      return;
    }

    _isInstallingPlatformio = true;
    _buildLogs = [
      'Установка PlatformIO Core через pip (может занять несколько минут)...',
      '',
    ];
    notifyListeners();

    _buildSubscription?.cancel();
    final stream = _service.installPlatformIO();

    _buildSubscription = stream.listen(
      (line) {
        _buildLogs.add(line);
        notifyListeners();
      },
      onDone: () async {
        _isInstallingPlatformio = false;

        if (_buildLogs.any((l) => l.contains('[SUCCESS]'))) {
          _platformioAvailable = await _service.isPlatformIOAvailable();
          if (_platformioAvailable) {
            await refreshPorts();
          }
        }

        notifyListeners();
      },
    );
  }

  Future<void> runPreflight() async {
    if (_isPreflightChecking || kIsWeb) return;

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
      final pkgs =
          await _service.platformioPkgList(_sourcePath!, _selectedDeviceType);
      final platformSpec = _projectInfo['platform']?.toString() ?? '';
      final baseName = platformSpec.split('@').first.trim();

      final platformPkgs = pkgs.where((p) => p['type'] == 'platform').toList();
      final frameworkPkgs =
          pkgs.where((p) => p['type'] == 'framework').toList();

      final platformMatch = baseName.isEmpty
          ? platformPkgs.isNotEmpty
          : platformPkgs.any((p) =>
              p['name']?.toString().contains(baseName) == true ||
              baseName.isEmpty);
      items.add(PreflightItem(
        'Платформа',
        ok: platformPkgs.isNotEmpty && (baseName.isEmpty || platformMatch),
        detail: platformPkgs.isNotEmpty
            ? platformPkgs.map((p) => '${p['name']}@${p['version']}').join(', ')
            : baseName.isEmpty
                ? 'не установлена'
                : '$baseName не установлена',
      ));

      items.add(PreflightItem(
        'Фреймворк',
        ok: frameworkPkgs.isNotEmpty,
        detail: frameworkPkgs.isNotEmpty
            ? frameworkPkgs
                .map((p) => '${p['name']}@${p['version']}')
                .join(', ')
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
    _downloadCancel?.cancel('Provider disposed');
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
