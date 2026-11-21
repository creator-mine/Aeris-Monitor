import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/device_ws_client.dart';
import '../../core/api/direct_device_client.dart';
import '../../core/config/connection_mode.dart';
import '../../models/device.dart';
import '../../models/log_entry.dart';
import '../../core/utils/log_translator.dart';
import '../../core/utils/csv_exporter.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/theme/app_theme.dart';
import '../settings/providers/settings_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

/// Live network logs for a single device.
///
/// Prefers the device WebSocket push channel (onLogsUpdate); an HTTP poll
/// of /api/v1/logs acts as a fallback so logs work even without WS support.
/// Entries from both channels are deduplicated by (ts, msg).
class LogsScreen extends StatefulWidget {
  final Device device;

  const LogsScreen({super.key, required this.device});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _maxEntries = 500;

  final DeviceWsClient _ws = DeviceWsClient();
  DirectDeviceClient? _http;
  Timer? _pollTimer;
  final ScrollController _scroll = ScrollController();

  final List<LogEntry> _logs = [];
  final Set<String> _seenKeys = {};
  bool _wsConnected = false;
  bool _autoScroll = true;
  bool _paused = false;

  Device get _device => widget.device;

  @override
  void initState() {
    super.initState();
    if (!LanPolicy.enabled) return;
    final baseUrl = _device.httpBaseUrl;
    if (baseUrl != null) {
      _http = DirectDeviceClient(baseUrl: baseUrl);
    }
    _ws
      ..onLogsUpdate = _mergeLogs
      ..onConnected = () {
        if (mounted) setState(() => _wsConnected = true);
        _ws.requestLogs();
      }
      ..onDisconnected = () {
        if (mounted) setState(() => _wsConnected = false);
      };
    _ws.connect(_device);

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _poll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ws
      ..onLogsUpdate = null
      ..onConnected = null
      ..onDisconnected = null
      ..disconnect();
    _http?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_paused || !LanPolicy.enabled) return;
    final http = _http;
    if (http == null) return;
    try {
      final fetched = await http.getLogs(limit: 50);
      if (mounted) _mergeLogs(fetched);
    } catch (_) {}
  }

  void _mergeLogs(List<LogEntry> fetched) {
    if (!mounted) return;
    var changed = false;
    for (final entry in fetched) {
      final key = '${entry.ts}:${entry.msg}';
      if (_seenKeys.add(key)) {
        _logs.add(entry);
        while (_logs.length > _maxEntries) {
          _seenKeys.remove('${_logs.first.ts}:${_logs.first.msg}');
          _logs.removeAt(0);
        }
        changed = true;
      }
    }
    if (!changed) return;
    setState(() {});
    if (_autoScroll && !_paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!LanPolicy.enabled) {
      return AppScaffold(
        title: _device.name,
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: TrText(
              'LAN отключён: журнал доступен только по локальной сети. '
              'Выключите «Только MQTT» в настройках.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }
    return AppScaffold(
      title: _device.name,
      actions: [
        IconButton(
          tooltip: L10n.of(context, 'Пауза'),
          icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
          onPressed: () => setState(() {
            _paused = !_paused;
            if (!_paused) _poll();
          }),
        ),
        IconButton(
          tooltip: L10n.of(context, 'Очистить'),
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: () {
            setState(() {
              _logs.clear();
              _seenKeys.clear();
            });
          },
        ),
        IconButton(
          tooltip: _autoScroll ? 'Автопрокрутка: вкл' : 'Автопрокрутка: выкл',
          icon: Icon(_autoScroll
              ? Icons.vertical_align_bottom
              : Icons.vertical_align_center),
          onPressed: () => setState(() => _autoScroll = !_autoScroll),
        ),
        IconButton(
          tooltip: L10n.of(context, 'Экспорт CSV'),
          icon: const Icon(Icons.save_alt),
          onPressed: _logs.isEmpty ? null : () => _exportCsv(settings),
        ),
      ],
      body: Column(
        children: [
          _buildStatusBar(),
          const Divider(height: 1),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: TrText(
                      'Логи пусты — ждём сообщений с устройства...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _logs.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      return _buildLogEntry(context, _logs[index], settings);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            _wsConnected ? Icons.wifi : Icons.wifi_off,
            size: 14,
            color: _wsConnected ? AppTheme.successColor : Colors.grey,
          ),
          const SizedBox(width: 6),
          TrText(
            _wsConnected ? 'WS: подключено' : 'WS: нет · HTTP polling',
            style: TextStyle(
              fontSize: 12,
              color: _wsConnected ? AppTheme.successColor : Colors.grey,
            ),
          ),
          const Spacer(),
          TrText(
            '${_logs.length} записей',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(
      BuildContext context, LogEntry entry, SettingsProvider settings) {
    final tagColor = switch (entry.tag) {
      'WiFi' => AppTheme.accentColors[2],
      'MQTT' => AppTheme.accentColors[0],
      'Boot' => AppTheme.accentColors[1],
      'Error' => AppTheme.errorColor,
      _ => AppTheme.primaryColor,
    };
    final msg = LogTranslator.display(
      settings.logMode,
      settings.language,
      entry.tag,
      entry.msg,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrText(
            '[${entry.ts}s]',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: TrText(
              entry.tag,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tagColor,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TrText(
              msg,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(SettingsProvider settings) async {
    final buffer = StringBuffer('ts,tag,msg\n');
    for (final entry in _logs) {
      buffer
        ..write(entry.ts)
        ..write(',')
        ..write(_csvField(entry.tag))
        ..write(',')
        ..write(_csvField(LogTranslator.display(
          settings.logMode,
          settings.language,
          entry.tag,
          entry.msg,
        )))
        ..write('\n');
    }

    final date =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = 'logs_${_device.id}_$date.csv';

    try {
      final path = await exportCsv(fileName, buffer.toString());
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: TrText('Логи сохранены: $path')),
        );
      } else if (path == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: TrText('Экспорт доступен только в настольной версии')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: TrText('Ошибка экспорта: $e')),
        );
      }
    }
  }

  String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
