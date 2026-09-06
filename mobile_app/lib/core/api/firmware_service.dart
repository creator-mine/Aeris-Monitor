import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

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

  Future<bool> isPlatformIOAvailable() async {
    try {
      final result = await Process.run('python', ['-m', 'platformio', '--version']);
      return result.exitCode == 0;
    } catch (_) {
      try {
        final result = await Process.run('platformio', ['--version']);
        return result.exitCode == 0;
      } catch (_) {
        return false;
      }
    }
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
        final result = await Process.run('ls', ['/dev/tty.*', '/dev/ttyUSB*', '/dev/ttyACM*']);
        if (result.exitCode == 0) {
          final output = result.stdout.toString().trim();
          ports.addAll(
            output
                .split('\n')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .map((s) => PortInfo(port: s)),
          );
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
    final script = p.join(root, 'penv', 'Scripts', 'python.exe');
    return Platform.isWindows && File(script).existsSync()
        ? script
        : Platform.isWindows
            ? null
            : p.join(root, 'penv', 'bin', 'python');
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
        final args = ['-m', 'platformio', 'run', '-e', environment];
        final process = await Process.start('python', args, workingDirectory: projectPath);
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
          '-m', 'platformio', 'run',
          '-e', environment,
          '--target', 'upload',
          '--upload-port', port,
        ];
        final process = await Process.start('python', args, workingDirectory: projectPath);
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

  Future<String?> getPlatformIOVersion() async {
    try {
      final result = await Process.run('python', ['-m', 'platformio', '--version']);
      if (result.exitCode == 0) {
        final line = result.stdout.toString().trim().split('\n').first;
        if (line.isNotEmpty) return line;
      }
    } catch (_) {}
    try {
      final result = await Process.run('platformio', ['--version']);
      if (result.exitCode == 0) {
        final line = result.stdout.toString().trim().split('\n').first;
        if (line.isNotEmpty) return line;
      }
    } catch (_) {}
    return null;
  }

  /// Lists installed packages (platforms/frameworks/tools) for an env.
  Future<List<Map<String, dynamic>>> platformioPkgList(
    String projectPath,
    String environment,
  ) async {
    try {
      final result = await Process.run(
        'python',
        ['-m', 'platformio', 'pkg', 'list', '--environment', environment, '--json-output'],
        workingDirectory: projectPath,
      );
      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout.toString());
        if (data is List) {
          return data.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {}
    return [];
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
