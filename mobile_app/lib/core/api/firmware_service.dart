import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../models/firmware_manifest.dart';
import 'ota_api.dart';

class BuildResult {
  final bool success;
  final String message;
  final int? exitCode;

  const BuildResult({required this.success, required this.message, this.exitCode});
}

class PortInfo {
  final String port;
  final String description;

  const PortInfo({required this.port, this.description = ''});
}

class ChipDetectionResult {
  final bool success;
  final String? chip;
  final String message;

  const ChipDetectionResult({required this.success, this.chip, required this.message});
}

class FirmwareService {
  Process? _activeProcess;

  Map<String, String> _pythonEnv() {
    return {
      ...Platform.environment,
      'PYTHONIOENCODING': 'utf-8',
      'PYTHONUTF8': '1',
    };
  }

  /// Python interpreters bundled in the PlatformIO isolated environment
  /// (created by the official installer) — checked before system Python.
  List<String> _penvPythonCandidates() {
    final root = _platformioRoot();
    if (root == null) return const [];
    return [
      p.join(root, 'penv', 'Scripts', 'python.exe'),
      p.join(root, 'penv', 'bin', 'python'),
      p.join(root, 'penv', 'bin', 'python3'),
    ];
  }

  /// Direct `platformio` launchers (penv + ~/.local/bin from the installer).
  List<String> _pioExecutableCandidates() {
    final list = <String>[];
    final root = _platformioRoot();
    if (root != null) {
      list.add(p.join(root, 'penv', 'Scripts', 'platformio.exe'));
      list.add(p.join(root, 'penv', 'bin', 'platformio'));
    }
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      list.add(p.join(home, '.local', 'bin', 'platformio'));
    }
    return list;
  }

  /// First Python interpreter that answers `--version`.
  Future<String?> _resolvePython() async {
    final candidates = Platform.isWindows
        ? ['python', 'py', 'python3']
        : ['python3', 'python'];
    for (final candidate in candidates) {
      try {
        final r = await Process.run(candidate, ['--version']);
        if (r.exitCode == 0) return candidate;
      } catch (_) {}
    }
    return null;
  }

  /// Whether [python] can create virtual environments (needs the `venv`
  /// and `ensurepip` modules, which Debian/Ubuntu ship separately).
  Future<bool> _hasVenv(String python) async {
    try {
      final r = await Process.run(python, ['-c', 'import venv, ensurepip']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Localized venv package name for the given interpreter, e.g.
  /// `python3.14-venv`, falling back to the generic `python3-venv`.
  Future<String> _venvPackageName(String python) async {
    try {
      final r = await Process.run(
        python,
        ['-c', 'import sys; print("%d.%d" % sys.version_info[:2])'],
      );
      if (r.exitCode == 0) {
        final v = r.stdout.toString().trim();
        if (v.isNotEmpty) return 'python$v-venv';
      }
    } catch (_) {}
    return 'python3-venv';
  }

  Future<String?> _tryPlatformio(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args, environment: _pythonEnv());
      if (r.exitCode == 0) {
        final out = r.stdout.toString().trim();
        final line = out.isEmpty ? '' : out.split('\n').first.trim();
        return line.isNotEmpty ? line : 'platformio';
      }
    } catch (_) {}
    return null;
  }

  /// Detects PlatformIO from the isolated env, launchers or system Python.
  /// Returns the version string, or null when it is not installed.
  Future<String?> _detectPlatformioVersion() async {
    for (final py in _penvPythonCandidates()) {
      if (!File(py).existsSync()) continue;
      final v = await _tryPlatformio(py, ['-m', 'platformio', '--version']);
      if (v != null) return v;
    }
    for (final exe in _pioExecutableCandidates()) {
      if (!File(exe).existsSync()) continue;
      final v = await _tryPlatformio(exe, ['--version']);
      if (v != null) return v;
    }
    for (final py in ['python', 'python3']) {
      final v = await _tryPlatformio(py, ['-m', 'platformio', '--version']);
      if (v != null) return v;
    }
    return _tryPlatformio('platformio', ['--version']);
  }

  Future<bool> isPlatformIOAvailable() async =>
      (await _detectPlatformioVersion()) != null;

  static const _platformioInstallerUrl =
      'https://raw.githubusercontent.com/platformio/platformio-core-installer/'
      'master/get-platformio.py';

  /// Downloads [url] to [dest] using curl, wget or Python's urllib.
  Future<bool> _downloadFile(String url, String dest) async {
    Future<bool> tryRun(String exe, List<String> args) async {
      try {
        final r = await Process.run(exe, args);
        return r.exitCode == 0 &&
            File(dest).existsSync() &&
            File(dest).lengthSync() > 0;
      } catch (_) {
        return false;
      }
    }

    if (await tryRun('curl', ['-fsSL', '-o', dest, url])) return true;
    if (await tryRun('wget', ['-q', '-O', dest, url])) return true;
    final python = await _resolvePython();
    if (python != null) {
      const code = 'import sys, urllib.request\n'
          'urllib.request.urlretrieve(sys.argv[1], sys.argv[2])';
      if (await tryRun(python, ['-c', code, url, dest])) return true;
    }
    return false;
  }

  /// Installs PlatformIO Core with the official installer script, which sets
  /// up an isolated `~/.platformio/penv` environment (used later for esptool).
  /// On Debian/Ubuntu it may require `python3-venv`/`python3-pip`.
  Stream<String> installPlatformIO() async* {
    final controller = StreamController<String>();

    () async {
      Directory? tmpDir;
      try {
        controller.add('Поиск Python...');
        final python = await _resolvePython();
        if (python == null) {
          controller.add('[ERROR] Python 3 не найден. Установите Python 3 '
              '(например: sudo apt install python3) и повторите.');
          return;
        }
        controller.add('Python: $python');

        if (!Platform.isWindows && !await _hasVenv(python)) {
          final pkg = await _venvPackageName(python);
          controller.add('');
          controller.add('[ERROR] В Python отсутствует модуль venv — без него '
              'PlatformIO установить нельзя.');
          controller.add('Установите его один раз (нужны права администратора) '
              'и нажмите кнопку снова:');
          controller.add('    sudo apt install $pkg python3-pip');
          return;
        }

        tmpDir = await Directory.systemTemp.createTemp('pio_install_');
        final scriptPath = p.join(tmpDir.path, 'get-platformio.py');

        controller.add('Загрузка официального установщика PlatformIO...');
        final downloaded = await _downloadFile(_platformioInstallerUrl, scriptPath);
        if (!downloaded) {
          controller.add('[ERROR] Не удалось скачать установщик. '
              'Проверьте подключение к интернету и повторите.');
          return;
        }
        controller.add('Файл: $scriptPath');
        controller.add('');

        final process = await Process.start(
          python,
          [scriptPath],
          environment: _pythonEnv(),
        );
        _activeProcess = process;

        final stderrFilter = _InstallerStderrFilter(controller.add);

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(controller.add);

        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(stderrFilter.add, onDone: stderrFilter.finish);

        final exitCode = await process.exitCode;
        _activeProcess = null;
        stderrFilter.finish();

        controller.add('');
        if (exitCode == 0) {
          controller.add('[SUCCESS] PlatformIO установлен');
        } else {
          controller.add('[ERROR] Установка не удалась (код: $exitCode)');
          if (!Platform.isWindows) {
            controller.add('Если не хватает зависимостей, установите их: '
                'sudo apt install python3-venv python3-pip');
          }
        }
      } catch (e) {
        _activeProcess = null;
        controller.add('[ERROR] $e');
      } finally {
        if (tmpDir != null) {
          try {
            await tmpDir.delete(recursive: true);
          } catch (_) {}
        }
        await controller.close();
      }
    }();

    yield* controller.stream;
  }

  /// Command prefix for PlatformIO: the isolated penv Python, a launcher, or
  /// system Python. Build/upload must use the same interpreter as detection,
  /// otherwise `python` alone fails when PlatformIO lives in `~/.platformio`.
  List<String> _platformioCommand() {
    final py = _penvPythonPath();
    if (py != null && File(py).existsSync()) {
      return [py, '-m', 'platformio'];
    }
    for (final exe in _pioExecutableCandidates()) {
      if (File(exe).existsSync()) return [exe];
    }
    return Platform.isWindows
        ? ['python', '-m', 'platformio']
        : ['python3', '-m', 'platformio'];
  }

  void cancelActiveProcess() {
    _activeProcess?.kill();
    _activeProcess = null;
  }

  Future<List<String>> getAvailablePorts() async {
    final infos = await getAvailablePortsWithInfo();
    return infos.map((i) => i.port).toList();
  }

  /// Returns serial ports together with their USB device description
  /// (e.g. "USB-SERIAL CH340", "Espressif USB JTAG/serial debug unit").
  Future<List<PortInfo>> getAvailablePortsWithInfo() async {
    final ports = <PortInfo>[];

    if (Platform.isWindows) {
      ports.addAll(await _windowsPnpPorts());
      if (ports.isEmpty) {
        ports.addAll(await _windowsSerialPorts());
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      try {
        final dev = Directory('/dev');
        if (await dev.exists()) {
          final entries = await dev.list().toList();
          for (final entity in entries) {
            final name = p.basename(entity.path);
            final matches = Platform.isLinux
                ? name.startsWith('ttyUSB') || name.startsWith('ttyACM')
                : name.startsWith('tty.') || name.startsWith('cu.');
            if (matches) {
              ports.add(PortInfo(port: entity.path));
            }
          }
        }
      } catch (_) {}
    }

    return ports;
  }

  Future<List<PortInfo>> _windowsPnpPorts() async {
    final ports = <PortInfo>[];
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; '
              'Get-PnpDevice -Class Ports -PresentOnly | Select-Object -ExpandProperty FriendlyName',
        ],
        stdoutEncoding: utf8,
      );
      if (result.exitCode == 0) {
        final trailingCom = RegExp(r'\s*\((COM\d+)\)\s*$');
        for (final raw in result.stdout.toString().split('\n')) {
          final name = raw.trim();
          if (name.isEmpty) continue;
          final match = trailingCom.firstMatch(name);
          if (match != null) {
            ports.add(PortInfo(
              port: match.group(1)!,
              description: name.replaceFirst(trailingCom, '').trim(),
            ));
          }
        }
      }
    } catch (_) {}
    return ports;
  }

  Future<List<PortInfo>> _windowsSerialPorts() async {
    final ports = <PortInfo>[];
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; '
              'Get-CimInstance Win32_SerialPort | ForEach-Object { "\$(\$_.DeviceID)|\$(\$_.Description)" }',
        ],
        stdoutEncoding: utf8,
      );
      if (result.exitCode == 0) {
        for (final raw in result.stdout.toString().split('\n')) {
          final line = raw.trim();
          if (!line.contains('|')) continue;
          final parts = line.split('|');
          if (parts.isNotEmpty) {
            ports.add(PortInfo(
              port: parts[0].trim(),
              description: parts.length > 1 ? parts[1].trim() : '',
            ));
          }
        }
      }
    } catch (_) {}
    return ports;
  }

  Future<ChipDetectionResult> detectChipOnPort(String port) async {
    final python = _penvPythonPath();
    final esptool = _esptoolScriptPath();

    if (python == null || esptool == null) {
      return const ChipDetectionResult(
        success: false,
        message: 'esptool не найден. Установите PlatformIO и соберите проект хотя бы один раз.',
      );
    }

    try {
      final result = await Process.run(
        python,
        [esptool, '--port', port, 'chip_id'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 25));

      final output = '${result.stdout.toString()}\n${result.stderr.toString()}';

      final match = RegExp(r'Chip is (\S+)').firstMatch(output);
      if (match != null) {
        return ChipDetectionResult(
          success: true,
          chip: match.group(1),
          message: output.trim(),
        );
      }

      return ChipDetectionResult(
        success: false,
        message: '${_trimDiagnostic(output)}\n'
            'Возможно, нужно зажать кнопку BOOT во время опроса.',
      );
    } on TimeoutException {
      return const ChipDetectionResult(
        success: false,
        message: 'Тайм-аут опроса порта. Проверьте соединение и попробуйте ещё раз.',
      );
    } catch (e) {
      return ChipDetectionResult(success: false, message: 'Ошибка: $e');
    }
  }

  String? _penvPythonPath() {
    final root = _platformioRoot();
    if (root == null) return null;
    final candidates = [
      p.join(root, 'penv', 'Scripts', 'python.exe'),
      p.join(root, 'penv', 'bin', 'python'),
      p.join(root, 'penv', 'bin', 'python3'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  String? _esptoolScriptPath() {
    final root = _platformioRoot();
    if (root == null) return null;
    final packages = Directory(p.join(root, 'packages'));
    if (!packages.existsSync()) return null;
    for (final dir in packages.listSync()) {
      if (dir is! Directory) continue;
      if (!p.basename(dir.path).startsWith('tool-esptoolpy')) continue;
      final script = File(p.join(dir.path, 'esptool.py'));
      if (script.existsSync()) return script.path;
    }
    return null;
  }

  String? _platformioRoot() {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return p.join(home, '.platformio');
  }

  String _trimDiagnostic(String output) {
    final lines = output
        .trim()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return 'Чип не определён.';
    final count = lines.length;
    var text = lines.sublist(count > 4 ? count - 4 : 0).join('\n');
    if (text.length > 400) text = text.substring(text.length - 400);
    return text;
  }

  Stream<String> buildFirmware(String projectPath, String environment) async* {
    final controller = StreamController<String>();

    () async {
      try {
        final args = ['run', '-e', environment];
        final cmd = _platformioCommand();
        final process = await Process.start(
          cmd.first,
          [...cmd.skip(1), ...args],
          workingDirectory: projectPath,
          environment: _pythonEnv(),
        );
        _activeProcess = process;

        process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          controller.add(line);
        });

        process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          controller.add('[STDERR] $line');
        });

        final exitCode = await process.exitCode;
        _activeProcess = null;

        controller.add('');
        if (exitCode == 0) {
          controller.add('[SUCCESS] Build completed');
        } else {
          controller.add('[ERROR] Build failed (code: $exitCode)');
        }
      } catch (e) {
        _activeProcess = null;
        controller.add('[ERROR] $e');
      } finally {
        await controller.close();
      }
    }();

    yield* controller.stream;
  }

  Stream<String> uploadFirmware(
    String projectPath,
    String environment,
    String port,
  ) async* {
    final controller = StreamController<String>();

    () async {
      try {
        final args = [
          'run',
          '-e', environment,
          '--target', 'upload',
          '--upload-port', port,
        ];
        final cmd = _platformioCommand();
        final process = await Process.start(
          cmd.first,
          [...cmd.skip(1), ...args],
          workingDirectory: projectPath,
          environment: _pythonEnv(),
        );
        _activeProcess = process;

        process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          controller.add(line);
        });

        process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          controller.add('[STDERR] $line');
        });

        final exitCode = await process.exitCode;
        _activeProcess = null;

        controller.add('');
        if (exitCode == 0) {
          controller.add('[SUCCESS] Upload completed');
        } else {
          controller.add('[ERROR] Upload failed (code: $exitCode)');
        }
      } catch (e) {
        _activeProcess = null;
        controller.add('[ERROR] $e');
      } finally {
        await controller.close();
      }
    }();

    yield* controller.stream;
  }

  /// sha256 hex of any binary file (used when importing an external firmware).
  Future<String> sha256OfFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Flashes a standalone firmware binary with esptool directly (no project).
  /// The app is written at the standard factory slot offset (0x10000).
  Stream<String> flashBinary(String binPath, String port) async* {
    final controller = StreamController<String>();

    () async {
      try {
        final python = _penvPythonPath();
        final esptool = _esptoolScriptPath();
        if (python == null || esptool == null) {
          controller.add('[ERROR] esptool не найден. Установите PlatformIO '
              'или соберите проект хотя бы один раз.');
          return;
        }
        if (!File(binPath).existsSync()) {
          controller.add('[ERROR] Файл не найден: $binPath');
          return;
        }

        final args = [
          esptool,
          '--chip', 'auto',
          '--port', port,
          '--baud', '460800',
          'write_flash',
          '0x10000', binPath,
        ];
        final process = await Process.start(
          python,
          args,
          environment: _pythonEnv(),
        );
        _activeProcess = process;

        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(controller.add);

        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) => controller.add('[STDERR] $line'));

        final exitCode = await process.exitCode;
        _activeProcess = null;

        controller.add('');
        if (exitCode == 0) {
          controller.add('[SUCCESS] Flash completed');
        } else {
          controller.add('[ERROR] Flash failed (code: $exitCode)');
        }
      } catch (e) {
        _activeProcess = null;
        controller.add('[ERROR] $e');
      } finally {
        await controller.close();
      }
    }();

    yield* controller.stream;
  }

  Future<String> calculateSourceHash(String projectPath) async {
    final StringBuffer buffer = StringBuffer();
    final srcDir = Directory(p.join(projectPath, 'src'));
    final includeDir = Directory(p.join(projectPath, 'include'));

    if (await srcDir.exists()) {
      await _hashDirectory(srcDir, buffer);
    }
    if (await includeDir.exists()) {
      await _hashDirectory(includeDir, buffer);
    }

    final platformioFile = File(p.join(projectPath, 'platformio.ini'));
    if (await platformioFile.exists()) {
      buffer.write(await platformioFile.readAsString());
    }

    final bytes = utf8.encode(buffer.toString());
    return md5.convert(bytes).toString();
  }

  Future<void> _hashDirectory(Directory dir, StringBuffer buffer) async {
    final entities = await dir.list(recursive: true).toList();
    final files = entities
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.cpp') ||
            f.path.endsWith('.h') ||
            f.path.endsWith('.ini'))
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      buffer.write(await file.readAsString());
    }
  }

  String findFirmwareBin(String projectPath, String environment) {
    return p.join(projectPath, '.pio', 'build', environment, 'firmware.bin');
  }

  Future<bool> isFirmwareBuilt(String projectPath, String environment) async {
    final binFile = File(findFirmwareBin(projectPath, environment));
    try {
      return await binFile.exists();
    } catch (_) {
      return false;
    }
  }

  /// Parses the real `FIRMWARE_VERSION` from include/config.h (or "" if missing).
  Future<String> getFirmwareVersionFromConfig(String projectPath) async {
    try {
      final configFile = File(p.join(projectPath, 'include', 'config.h'));
      if (!await configFile.exists()) return '';
      final content = await configFile.readAsString();
      final match = RegExp(
        r'#define\s+FIRMWARE_VERSION\s+"([^"]+)"',
      ).firstMatch(content);
      return match?.group(1)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Fetches the published firmware manifest from the OTA site
  /// for the given device type (defaults to the legacy esp32-c3 manifest).
  /// [baseUrl] overrides the default OTA host (self-hosting).
  Future<FirmwareManifest?> fetchOtaManifest({
    String? deviceType,
    String? baseUrl,
  }) async {
    return OtaApi(baseUrl: baseUrl).fetchManifest(deviceType: deviceType);
  }

  /// Parses [platformio.ini] and returns the settings of the selected env
  /// (board, platform, framework, speeds, custom flags etc.).
  Future<Map<String, dynamic>> getProjectInfo(String projectPath, String environment) async {
    final platformioFile = File(p.join(projectPath, 'platformio.ini'));
    if (!await platformioFile.exists()) {
      return {'error': 'platformio.ini not found'};
    }

    final content = await platformioFile.readAsString();
    final targetEnv = 'env:$environment';
    final envNames = <String>[];
    final info = <String, dynamic>{'path': projectPath, 'environments': envNames};
    final sectionRe = RegExp(r'^\s*\[([^\]]+)\]\s*$');
    final kvRe = RegExp(r'^\s*([^#\s=;][^=]*?)\s*=\s*(.*?)\s*$');

    var inTarget = false;
    for (final raw in content.split('\n')) {
      final sectionMatch = sectionRe.firstMatch(raw);
      if (sectionMatch != null) {
        final secName = sectionMatch.group(1)!.trim();
        if (secName.startsWith('env:')) {
          envNames.add(secName.substring(4).trim());
        }
        inTarget = secName == targetEnv;
        continue;
      }
      if (!inTarget) continue;
      final kv = kvRe.firstMatch(raw);
      if (kv != null) {
        info.putIfAbsent(kv.group(1)!.trim(), () => kv.group(2)!.trim());
      }
    }

    info['envName'] = environment;
    return info;
  }

  Future<Map<String, dynamic>> getFirmwareBinInfo(String projectPath, String environment) async {
    final binPath = findFirmwareBin(projectPath, environment);
    final file = File(binPath);
    final exists = await file.exists();
    return {
      'exists': exists,
      'path': binPath,
      'sizeBytes': exists ? await file.length() : null,
      'modified': exists ? await file.lastModified() : null,
    };
  }

  /// Captures the build configuration (include headers + platformio.ini)
  /// at build time so a saved version keeps its own config snapshot.
  Future<Map<String, dynamic>> captureConfigSnapshot(String projectPath) async {
    final files = <String, String>{};

    final includeDir = Directory(p.join(projectPath, 'include'));
    if (await includeDir.exists()) {
      await for (final entity in includeDir.list()) {
        if (entity is File) {
          try {
            files[p.relative(entity.path, from: projectPath)] =
                await entity.readAsString();
          } catch (_) {}
        }
      }
    }

    final platformioFile = File(p.join(projectPath, 'platformio.ini'));
    if (await platformioFile.exists()) {
      try {
        files['platformio.ini'] = await platformioFile.readAsString();
      } catch (_) {}
    }

    return {
      'files': files,
      'capturedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Computes a per-file md5 map (relative path -> hash) so the app can
  /// show which files changed since the last saved build.
  Future<Map<String, String>> calculateSourceFileHashes(String projectPath) async {
    final result = <String, String>{};

    final srcDir = Directory(p.join(projectPath, 'src'));
    final includeDir = Directory(p.join(projectPath, 'include'));

    await _collectFileHashes(srcDir, projectPath, result);
    await _collectFileHashes(includeDir, projectPath, result);

    final platformioFile = File(p.join(projectPath, 'platformio.ini'));
    if (await platformioFile.exists()) {
      result['platformio.ini'] = md5.convert(await platformioFile.readAsBytes()).toString();
    }

    return result;
  }

  Future<void> _collectFileHashes(Directory dir, String projectPath, Map<String, String> out) async {
    if (!await dir.exists()) return;
    final entities = await dir.list(recursive: true).toList();
    for (final entity in entities.whereType<File>()) {
      if (entity.path.endsWith('.cpp') || entity.path.endsWith('.h')) {
        out[p.relative(entity.path, from: projectPath)] =
            md5.convert(await entity.readAsBytes()).toString();
      }
    }
  }

  Future<String?> getPlatformIOVersion() => _detectPlatformioVersion();

  /// Lists installed packages (platforms/frameworks/tools) for an env.
  ///
  /// `pio pkg list` has no JSON output on Core 6.x, so its human-readable
  /// tree is parsed instead. UTF-8 is forced both in the environment (PIO
  /// draws box characters and crashes on a cp1251 console) and when decoding
  /// stdout, otherwise the tree glyphs come back garbled.
  Future<List<Map<String, dynamic>>> platformioPkgList(
    String projectPath,
    String environment,
  ) async {
    try {
      final cmd = _platformioCommand();
      final result = await Process.run(
        cmd.first,
        [...cmd.skip(1), 'pkg', 'list', '--environment', environment],
        workingDirectory: projectPath,
        environment: _pythonEnv(),
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode == 0) {
        return _parsePkgList(result.stdout.toString());
      }
    } catch (_) {}
    return [];
  }

  List<Map<String, dynamic>> _parsePkgList(String text) {
    final packages = <Map<String, dynamic>>[];
    final platformRe = RegExp(r'^Platform\s+(\S+)\s+@\s+([^\s(]+)');
    final frameworkRe =
        RegExp(r'^[\s\W]*?(framework-[\w.\-]+)\s+@\s+([^\s(]+)');
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final platform = platformRe.firstMatch(trimmed);
      if (platform != null) {
        packages.add({
          'type': 'platform',
          'name': platform.group(1),
          'version': platform.group(2),
        });
        continue;
      }
      final framework = frameworkRe.firstMatch(trimmed);
      if (framework != null) {
        packages.add({
          'type': 'framework',
          'name': framework.group(1),
          'version': framework.group(2),
        });
      }
    }
    return packages;
  }

  /// Basic git info about the project source (branch / last commit).
  Future<Map<String, dynamic>> getGitInfo(String projectPath) async {
    try {
      if (!await Directory(p.join(projectPath, '.git')).exists()) {
        return {'isRepo': false};
      }

      Future<String?> run(List<String> args) async {
        try {
          final r = await Process.run('git', ['-C', projectPath, ...args]);
          if (r.exitCode == 0) {
            final text = r.stdout.toString().trim();
            return text.isEmpty ? null : text;
          }
        } catch (_) {}
        return null;
      }

      final branch = await run(['rev-parse', '--abbrev-ref', 'HEAD']);
      final commitLog = await run(['log', '-1', '--format=%h|%ad|%s', '--date=short']);

      String? commit;
      String? date;
      String? message;
      if (commitLog != null) {
        final parts = commitLog.split('|');
        commit = parts.isNotEmpty ? parts[0].trim() : null;
        date = parts.length > 1 ? parts[1].trim() : null;
        message = parts.length > 2 ? parts[2].trim() : null;
      }

      return {
        'isRepo': true,
        'branch': branch ?? '—',
        'commit': commit ?? '—',
        'date': date ?? '—',
        'message': message ?? '',
      };
    } catch (_) {
      return {'isRepo': false};
    }
  }
}

/// Drops the harmless multiprocessing/shutil finalizer traceback that the
/// PlatformIO installer prints on some Python versions (3.12+/3.14) while it
/// removes its own temporary directory. Any other stderr is passed through
/// unchanged, prefixed with `[STDERR] `.
class _InstallerStderrFilter {
  _InstallerStderrFilter(this._emit);

  final void Function(String line) _emit;

  static const _benignMarkers = <String>[
    '/multiprocessing/',
    'multiprocessing/util.py',
    '_run_finalizers',
    '_remove_temp_dir',
    '_rmtree',
    'orig_st = os.lstat',
    'finalizer()',
    'self._callback(',
    'res = self._callback',
    'pymp-',
    '.piocore-installer-',
    'FileNotFoundError: [Errno 2] No such file or directory:',
  ];

  final List<String> _buffer = [];
  bool _inTraceback = false;
  bool _benign = false;

  void add(String line) {
    if (!_inTraceback) {
      if (line.trimLeft().startsWith('Traceback (most recent call last):')) {
        _inTraceback = true;
        _benign = false;
        _buffer
          ..clear()
          ..add(line);
        return;
      }
      _emit('[STDERR] $line');
      return;
    }

    _buffer.add(line);
    if (_benignMarkers.any(line.contains)) _benign = true;

    // A traceback block ends with the exception line, which is not indented.
    final startsIndented = line.startsWith(' ') || line.startsWith('\t');
    if (!startsIndented) _flush();
  }

  void finish() => _flush();

  void _flush() {
    if (_buffer.isNotEmpty && !_benign) {
      for (final line in _buffer) {
        _emit('[STDERR] $line');
      }
    }
    _buffer.clear();
    _inTraceback = false;
    _benign = false;
  }
}
