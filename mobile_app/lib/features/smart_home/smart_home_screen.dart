import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device.dart';
import '../../models/smart_rule.dart';
import '../../core/config/app_config.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/loading_indicator.dart';
import '../../shared/widgets/error_widget.dart';
import '../../shared/theme/app_theme.dart';
import '../devices/providers/devices_provider.dart';
import 'providers/smart_home_provider.dart';

String ruleTriggerLabel(RuleTrigger trigger) => switch (trigger) {
      RuleTrigger.thresholdAbove => 'Порог: выше',
      RuleTrigger.thresholdBelow => 'Порог: ниже',
      RuleTrigger.online => 'Устройство в сети',
      RuleTrigger.offline => 'Устройство пропало',
      RuleTrigger.noData => 'Нет данных',
    };

String ruleActionLabel(RuleAction action) => switch (action) {
      RuleAction.notify => 'Уведомление',
      RuleAction.mqttCommand => 'MQTT-команда',
      RuleAction.deviceCommand => 'Команда на устройство',
    };

IconData ruleActionIcon(RuleAction action) => switch (action) {
      RuleAction.notify => Icons.notifications_active_outlined,
      RuleAction.mqttCommand => Icons.swap_calls,
      RuleAction.deviceCommand => Icons.memory_outlined,
    };

String describeRule(SmartRule rule, {required String Function(String) deviceName}) {
  final trigger = switch (rule.trigger) {
    RuleTrigger.thresholdAbove => '${rule.sensorType} > ${rule.threshold}',
    RuleTrigger.thresholdBelow => '${rule.sensorType} < ${rule.threshold}',
    RuleTrigger.online => 'появление в сети',
    RuleTrigger.offline => 'пропадание из сети',
    RuleTrigger.noData => 'нет данных с устройства',
  };
  final action = switch (rule.action) {
    RuleAction.notify => 'уведомление',
    RuleAction.mqttCommand => 'MQTT: ${rule.actionPayload}',
    RuleAction.deviceCommand => 'команда: ${rule.actionPayload}',
  };
  return '${deviceName(rule.deviceId)} · $trigger · $action';
}

class SmartHomeScreen extends StatefulWidget {
  const SmartHomeScreen({super.key});

  @override
  State<SmartHomeScreen> createState() => _SmartHomeScreenState();
}

class _SmartHomeScreenState extends State<SmartHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final devicesProvider = context.read<DevicesProvider>();
      if (devicesProvider.devices.isEmpty) {
        devicesProvider.loadDevices();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Умный дом',
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Добавить правило',
          onPressed: () => _openEditor(context, rule: null),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => context.read<SmartHomeProvider>().loadRules(),
        ),
      ],
      body: Consumer<SmartHomeProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.rules.isEmpty) {
            return const LoadingIndicator(message: 'Загрузка правил...');
          }
          if (provider.error != null && provider.rules.isEmpty) {
            return AppErrorWidget(
              message: provider.error!,
              onRetry: () => provider.loadRules(),
            );
          }
          if (provider.rules.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Нет правил',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Создайте правило: при превышении порога\nотправить команду или уведомить',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _openEditor(context, rule: null),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить правило'),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => provider.loadRules(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.rules.length,
              itemBuilder: (context, index) {
                return _buildRuleCard(context, provider, provider.rules[index]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildRuleCard(
    BuildContext context,
    SmartHomeProvider provider,
    SmartRule rule,
  ) {
    final enabled = rule.enabled;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (enabled ? AppTheme.primaryColor : Colors.grey)
              .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            ruleActionIcon(rule.action),
            color: enabled ? AppTheme.primaryColor : Colors.grey,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                rule.name.isEmpty ? 'Правило' : rule.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (_) => provider.toggleRule(rule),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            describeRule(rule, deviceName: provider.deviceName),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
        onTap: () => _openEditor(context, rule: rule),
        trailing: IconButton(
          tooltip: 'Удалить',
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _confirmDelete(context, provider, rule),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {required SmartRule? rule}) async {
    final devices = context.read<DevicesProvider>().devices;
    await showDialog<void>(
      context: context,
      builder: (context) => RuleEditorDialog(
        rule: rule,
        devices: devices,
      ),
    );
  }

  void _confirmDelete(BuildContext context, SmartHomeProvider provider, SmartRule rule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить правило?'),
        content: Text('Правило «${rule.name.isEmpty ? 'Правило' : rule.name}» будет удалено.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await provider.deleteRule(rule.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}

class RuleEditorDialog extends StatefulWidget {
  final SmartRule? rule;
  final List<Device> devices;

  const RuleEditorDialog({
    super.key,
    required this.rule,
    required this.devices,
  });

  @override
  State<RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<RuleEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _manualDeviceController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _payloadController;
  late final TextEditingController _cooldownController;

  late String? _deviceId;
  late RuleTrigger _trigger;
  late String _sensorType;
  late RuleAction _action;

  bool get _isNew => widget.rule == null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _manualDeviceController = TextEditingController();
    _thresholdController = TextEditingController(
      text: rule?.threshold?.toString() ?? '',
    );
    _payloadController = TextEditingController(text: rule?.actionPayload ?? '');
    _cooldownController = TextEditingController(
      text: '${rule?.cooldownSeconds ?? 60}',
    );
    _deviceId = rule?.deviceId;
    _trigger = rule?.trigger ?? RuleTrigger.thresholdAbove;
    _sensorType = rule?.sensorType ?? '';
    _action = rule?.action ?? RuleAction.notify;
  }

  bool get _isThresholdTrigger =>
      _trigger == RuleTrigger.thresholdAbove || _trigger == RuleTrigger.thresholdBelow;

  bool get _needsPayload =>
      _action == RuleAction.mqttCommand || _action == RuleAction.deviceCommand;

  List<String> get _sensorOptions {
    final result = <String>{};
    final index = widget.devices.indexWhere((d) => d.id == _deviceId);
    if (index != -1) {
      for (final metric in widget.devices[index].allMetrics) {
        result.add(metric.key);
      }
    }
    result.addAll(AppConfig.defaultSensorNames.keys);
    return result.toList()..sort();
  }

  List<String> get _deviceOptions {
    final ids = widget.devices.map((d) => d.id).toSet();
    if (_deviceId != null) ids.add(_deviceId!);
    return ids.toList()..sort();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _manualDeviceController.dispose();
    _thresholdController.dispose();
    _payloadController.dispose();
    _cooldownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Новое правило' : 'Редактировать правило'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  hintText: 'Например: Жара под потолком',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _deviceId,
                decoration: const InputDecoration(labelText: 'Устройство'),
                items: _deviceOptions
                    .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _deviceId = value;
                    _sensorType = '';
                  });
                },
              ),
              TextFormField(
                controller: _manualDeviceController,
                decoration: const InputDecoration(
                  labelText: 'Или ID устройства вручную',
                  hintText: 'Например: esp32c3_001',
                ),
                validator: (_) {
                  final id = _manualDeviceController.text.trim();
                  if (_deviceId == null && id.isEmpty) {
                    return 'Выберите устройство или введите ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<RuleTrigger>(
                initialValue: _trigger,
                decoration: const InputDecoration(labelText: 'Триггер'),
                items: RuleTrigger.values
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text(ruleTriggerLabel(t))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _trigger = value);
                },
              ),
              if (_isThresholdTrigger) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _sensorType.isEmpty ? null : _sensorType,
                  decoration: const InputDecoration(labelText: 'Датчик'),
                  items: _sensorOptions
                      .map((key) => DropdownMenuItem(value: key, child: Text(key)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _sensorType = value);
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _thresholdController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Порог'),
                  validator: (_) {
                    final v = double.tryParse(_thresholdController.text.trim());
                    if (v == null) return 'Введите число';
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<RuleAction>(
                initialValue: _action,
                decoration: const InputDecoration(labelText: 'Действие'),
                items: RuleAction.values
                    .map((a) =>
                        DropdownMenuItem(value: a, child: Text(ruleActionLabel(a))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _action = value);
                },
              ),
              if (_needsPayload) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _payloadController,
                  decoration: InputDecoration(
                    labelText: _action == RuleAction.mqttCommand
                        ? 'Команда (MQTT-топик iot/<id>/commands)'
                        : 'Команда на устройство (REST)',
                    hintText: 'Например: relay1_on',
                  ),
                  validator: (_) {
                    if (_payloadController.text.trim().isEmpty) {
                      return 'Укажите команду';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _cooldownController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Перерыв между срабатываниями, секунд',
                ),
                validator: (_) {
                  final v = int.tryParse(_cooldownController.text.trim());
                  if (v == null || v < 0) return 'Введите число >= 0';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final deviceId =
        _manualDeviceController.text.trim().isNotEmpty
            ? _manualDeviceController.text.trim()
            : _deviceId;
    if (deviceId == null) return;

    final provider = context.read<SmartHomeProvider>();
    final threshold = _isThresholdTrigger
        ? double.parse(_thresholdController.text.trim())
        : null;
    final existing = widget.rule;
    final base = SmartRule(
      id: existing?.id ?? '',
      name: _nameController.text.trim(),
      enabled: existing?.enabled ?? true,
      deviceId: deviceId,
      trigger: _trigger,
      sensorType: _isThresholdTrigger ? _sensorType : '',
      threshold: threshold,
      action: _action,
      actionPayload: _needsPayload ? _payloadController.text.trim() : '',
      cooldownSeconds: int.parse(_cooldownController.text.trim()),
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    final ok = existing == null
        ? await provider.createRule(base)
        : await provider.updateRule(base);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error ?? 'Не удалось сохранить правило')),
      );
    }
  }
}