import 'package:flutter/material.dart';

import '../../core/api/wifi_transport.dart';
import '../../models/wifi_profile.dart';
import '../../shared/theme/app_theme.dart';

/// Wi-Fi manager: works over HTTP (LAN) and USB serial.
class WifiScreen extends StatefulWidget {
  final WifiTransport transport;
  final String title;

  const WifiScreen({
    super.key,
    required this.transport,
    this.title = 'Wi-Fi сети',
  });

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  WifiStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = _status == null;
      _error = null;
    });
    try {
      final status = await widget.transport.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() => _busy = true);
    List<WifiScanEntry> results;
    try {
      results = await widget.transport.scan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final selected = await showModalBottomSheet<WifiScanEntry>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Найденные сети',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('ESP32 видит только 2,4 ГГц'),
              ),
              Flexible(
                child: results.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Сети не найдены'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final entry = results[index];
                          final saved = _profileFor(entry.ssid) != null;
                          return ListTile(
                            leading: Icon(entry.secure
                                ? Icons.lock_outline
                                : Icons.wifi),
                            title: Text(entry.ssid),
                            subtitle: Text(
                                '${entry.rssi} dBm · канал ${entry.channel}'
                                '${saved ? ' · сохранена' : ''}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(context, entry),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    final existing = _profileFor(selected.ssid);
    if (existing != null) {
      await _connect(existing);
    } else {
      await _addNetwork(prefillSsid: selected.ssid);
    }
  }

  WifiProfile? _profileFor(String ssid) {
    final profiles = _status?.profiles ?? const <WifiProfile>[];
    for (final p in profiles) {
      if (p.ssid == ssid) return p;
    }
    return null;
  }

  Future<void> _connect(WifiProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подключиться?'),
        content: Text(
            'Устройство переключится на сеть «${profile.ssid}». '
            'Связь может прерваться на несколько секунд.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подключиться'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => widget.transport.connect(profile.id),
        done: 'Переключаюсь на «${profile.ssid}»');
  }

  Future<void> _addNetwork({String? prefillSsid}) async {
    final status = _status;
    if (status != null && status.used >= status.max) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Достигнут лимит ${status.max} сетей')),
      );
      return;
    }
    final ssidController = TextEditingController(text: prefillSsid ?? '');
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить сеть'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: ssidController,
                decoration: const InputDecoration(labelText: 'SSID'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Введите SSID' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  helperText: 'Пусто — открытая сеть',
                ),
              ),
              const SizedBox(height: 8),
              const Text('Сохранится как новая сеть с низшим приоритетом.',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(context, true);
            },
            child: const Text('Сохранить и подключить'),
          ),
        ],
      ),
    );

    if (result != true) return;
    final ssid = ssidController.text.trim();
    final password = passwordController.text;

    await _run(() async {
      await widget.transport.add(
        ssid,
        password,
        (status?.used ?? 0) + 1,
      );
      final refreshed = await widget.transport.getStatus();
      if (mounted) setState(() => _status = refreshed);
      final added = _profileFor(ssid);
      if (added != null) await widget.transport.connect(added.id);
    }, done: 'Сеть «$ssid» сохранена');
  }

  Future<void> _remove(WifiProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сеть?'),
        content: Text('«${profile.ssid}» будет удалена из памяти устройства.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => widget.transport.remove(profile.id), done: 'Сеть удалена');
  }

  Future<void> _move(WifiProfile profile, int delta) async {
    final profiles = [...?_status?.profiles];
    profiles.sort((a, b) => a.priority.compareTo(b.priority));
    final index = profiles.indexWhere((p) => p.id == profile.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= profiles.length) return;
    final moved = profiles.removeAt(index);
    profiles.insert(target, moved);
    await _run(
      () => widget.transport.reorder(profiles.map((p) => p.id).toList()),
      done: 'Приоритет обновлён',
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && status == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildCurrent(context, status),
                      const SizedBox(height: 12),
                      if (widget.transport.canScan ||
                          widget.transport.canAdd)
                        Row(
                          children: [
                            if (widget.transport.canScan)
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _busy ? null : _scan,
                                  icon: const Icon(Icons.wifi_find),
                                  label: const Text('Сканировать'),
                                ),
                              ),
                            if (widget.transport.canAdd) ...[
                              if (widget.transport.canScan)
                                const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: (_busy ||
                                        (status != null &&
                                            status.used >= status.max))
                                    ? null
                                    : () => _addNetwork(),
                                icon: const Icon(Icons.add),
                                label: const Text('Вручную'),
                              ),
                            ],
                          ],
                        )
                      else
                        const Text(
                          'Удалённо можно переключаться только на сети, '
                          'которые уже сохранены на устройстве.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Сохранённые сети',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                          if (status != null)
                            Chip(
                              label: Text('${status.used}/${status.max}'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (status == null || status.profiles.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Пока нет сохранённых сетей. Нажмите «Сканировать».',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._sortedProfiles(status).map(
                          (profile) => _buildProfileTile(context, profile),
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        'ESP32 подключается только к одной сети одновременно '
                        'и переключается между сохранёнными по приоритету.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
    );
  }

  List<WifiProfile> _sortedProfiles(WifiStatus status) {
    final list = [...status.profiles];
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  Widget _buildCurrent(BuildContext context, WifiStatus? status) {
    final connected = status?.connected ?? false;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(
        darkMode: Theme.of(context).brightness == Brightness.dark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(connected ? Icons.wifi : Icons.wifi_off,
                  color: connected ? Colors.green : Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  connected
                      ? (status?.ssid.isNotEmpty == true
                          ? status!.ssid
                          : 'Подключено')
                      : 'Нет подключения',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              if (status?.manual == true)
                const Chip(
                  label: Text('Вручную'),
                  visualDensity: VisualDensity.compact,
                )
              else
                const Chip(
                  label: Text('Авто'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 4),
            Text('${status?.rssi ?? 0} dBm · ${status?.ip ?? ''}'),
          ],
          if (status?.manual == true && widget.transport.canAuto)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(widget.transport.setAuto,
                        done: 'Включён автовыбор'),
                child: const Text('Вернуть автовыбор'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(BuildContext context, WifiProfile profile) {
    final subtitle = [
      'Приоритет ${profile.priority}',
      if (profile.connected) 'подключена',
      if (!profile.enabled) 'выключена',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          profile.connected ? Icons.wifi : Icons.wifi_outlined,
          color: profile.connected ? Colors.green : null,
        ),
        title: Text(profile.ssid),
        subtitle: Text(subtitle),
        trailing: PopupMenuButton<String>(
          enabled: !_busy,
          onSelected: (value) {
            switch (value) {
              case 'connect':
                _connect(profile);
                break;
              case 'up':
                _move(profile, -1);
                break;
              case 'down':
                _move(profile, 1);
                break;
              case 'toggle':
                _run(
                  () => widget.transport.setEnabled(
                      profile.id, !profile.enabled),
                  done: profile.enabled ? 'Сеть выключена' : 'Сеть включена',
                );
                break;
              case 'remove':
                _remove(profile);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'connect',
              child: Text('Подключиться'),
            ),
            if (widget.transport.canEdit) ...[
              const PopupMenuItem(
                value: 'up',
                child: Text('Выше приоритет'),
              ),
              const PopupMenuItem(
                value: 'down',
                child: Text('Ниже приоритет'),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Text(profile.enabled ? 'Выключить' : 'Включить'),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Удалить'),
              ),
            ],
          ],
        ),
        onTap: profile.connected || _busy ? null : () => _connect(profile),
      ),
    );
  }
}
