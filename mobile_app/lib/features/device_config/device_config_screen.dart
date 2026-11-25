import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/device_config_provider.dart';
import '../../core/config/log_mode.dart';
import '../../core/api/wifi_transport.dart';
import '../wifi/wifi_screen.dart';
import '../../core/utils/log_translator.dart';
import '../../core/utils/version.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/theme/app_theme.dart';
import '../../models/log_entry.dart';
import '../settings/providers/settings_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

class DeviceConfigScreen extends StatefulWidget {
  const DeviceConfigScreen({super.key});

  @override
  State<DeviceConfigScreen> createState() => _DeviceConfigScreenState();
}

class _DeviceConfigScreenState extends State<DeviceConfigScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mqttUserController = TextEditingController();
  final TextEditingController _mqttPasswordController = TextEditingController();
  String? _selectedPort;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceConfigProvider>().loadDevices();
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _mqttUserController.dispose();
    _mqttPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Настройка',
      body: Consumer<DeviceConfigProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: () => provider.refreshPorts(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android) ...[
                  _buildAndroidNotice(),
                  const SizedBox(height: 16),
                ],
                _buildConnectionSection(context, provider),
                const SizedBox(height: 24),
                if (provider.isConnected) ...[
                  _buildInfoSection(context, provider),
                  const SizedBox(height: 24),
                  _buildFirmwareSection(context, provider),
                  const SizedBox(height: 24),
                  _buildWiFiSection(context, provider),
                  const SizedBox(height: 24),
                  _buildCredentialsSection(context, provider),
                  const SizedBox(height: 24),
                  _buildLogsSection(context, provider),
                ] else
                  _buildNoConnectionHint(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAndroidNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: TrText(
              'На телефоне настройка по USB недоступна. Подключитесь к точке '
              'доступа устройства (Aeris-Setup-XXXX) и откройте '
              'http://192.168.4.1, либо настройте Wi-Fi с компьютера.',
              style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionSection(
      BuildContext context, DeviceConfigProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TrText(
              'Подключение по USB',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: L10n.of(context, 'Обновить список портов'),
              onPressed: () => provider.refreshPorts(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.cardDecoration(
              darkMode: Theme.of(context).brightness == Brightness.dark),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedPort,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: L10n.of(context, 'COM-порт'),
                  prefixIcon: const Icon(Icons.usb),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                hint: const TrText('Выберите порт'),
                items: [
                  for (final port in provider.ports)
                    DropdownMenuItem(value: port, child: TrText(port)),
                ],
                onChanged: provider.isConnecting
                    ? null
                    : (port) => setState(() => _selectedPort = port),
              ),
              const SizedBox(height: 16),
              if (!provider.isConnected)
                FilledButton.icon(
                  onPressed: _selectedPort == null || provider.isConnecting
                      ? null
                      : () => _connect(context, provider, _selectedPort!),
                  icon: provider.isConnecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link, size: 18),
                  label: TrText(provider.isConnecting
                      ? 'Подключение...'
                      : 'Подключиться'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: provider.isReconnecting
                          ? Row(
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                TrText(
                                  'Устройство перезагружается, переподключаюсь...',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color),
                                ),
                              ],
                            )
                          : OutlinedButton.icon(
                              onPressed: () => _disconnect(context, provider),
                              icon: const Icon(Icons.link_off, size: 18),
                              label: const TrText('Отключиться'),
                            ),
                    ),
                  ],
                ),
              if (provider.error != null) ...[
                const SizedBox(height: 12),
                TrText(
                  '${provider.error}',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoConnectionHint() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 48),
          Icon(Icons.settings_input_component,
              size: 64, color: Colors.grey.shade500),
          const SizedBox(height: 16),
          TrText(
            'Подключите ESP32 по USB',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          TrText(
            'Выберите COM-порт и нажмите «Подключиться»',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(
      BuildContext context, DeviceConfigProvider provider) {
    final info = provider.info;
    final status = provider.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrText(
          'Информация об устройстве',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.cardDecoration(
              darkMode: Theme.of(context).brightness == Brightness.dark),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, Icons.memory, 'Прошивка',
                  (info?['firmware'] as String?) ?? '—'),
              _infoRow(
                  context,
                  Icons.wifi,
                  'Wi-Fi',
                  (status?['wifi_connected'] == true)
                      ? 'подключен'
                      : 'не подключен'),
              _infoRow(context, Icons.cloud, 'MQTT',
                  (status?['mqtt_enabled'] == true) ? 'включен' : 'отключен'),
              if (status?['uptime'] != null)
                _infoRow(context, Icons.timer, 'Аптайм',
                    _formatUptime((status!['uptime'] as num).toInt())),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(
      BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: TrText(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: TrText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatUptime(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '$dд $hч';
    if (h > 0) return '$hч $mм';
    return '$mм ${seconds % 60}с';
  }

  Widget _buildFirmwareSection(
      BuildContext context, DeviceConfigProvider provider) {
    final manifest = provider.manifest;
    final freshness = provider.freshness;
    final (color, icon, label) = switch (freshness) {
      FirmwareFreshness.outdated => (
          AppTheme.errorColor,
          Icons.system_update_alt,
          'Доступно обновление'
        ),
      FirmwareFreshness.latest => (
          AppTheme.successColor,
          Icons.check_circle_outline,
          'Прошивка актуальна'
        ),
      FirmwareFreshness.newer => (
          Colors.blue,
          Icons.published_with_changes,
          'Прошивка новее опубликованной'
        ),
      FirmwareFreshness.unknown => (
          Colors.grey,
          Icons.help_outline,
          'Актуальность не определена'
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TrText(
              'Прошивка',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
            ),
            IconButton(
              icon: provider.isCheckingManifest
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 20),
              tooltip: L10n.of(context, 'Проверить обновления'),
              onPressed: provider.isCheckingManifest
                  ? null
                  : () => provider.checkManifest(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.cardDecoration(
              darkMode: Theme.of(context).brightness == Brightness.dark),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(
                  context,
                  Icons.memory,
                  'На устройстве',
                  provider.firmwareVersion == null
                      ? '—'
                      : 'v${provider.firmwareVersion}'),
              _infoRow(
                context,
                Icons.cloud,
                'Опубликовано',
                manifest == null
                    ? '—'
                    : 'v${manifest.version} (${manifest.buildDateLabel})',
              ),
              if (provider.manifestError != null) ...[
                const SizedBox(height: 4),
                TrText(
                  provider.manifestError!,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TrText(
                        label,
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    ),
                  ],
                ),
              ),
              if (provider.isOutdated) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: provider.isSendingOta
                        ? null
                        : () => _showOtaDialog(context, provider),
                    icon: provider.isSendingOta
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt, size: 18),
                    label: TrText(provider.isSendingOta
                        ? 'Запуск обновления...'
                        : 'Обновить прошивку'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showOtaDialog(
      BuildContext context, DeviceConfigProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const TrText('Обновить прошивку?'),
        content: TrText(
          'Устройство (текущая v${provider.firmwareVersion ?? '—'}) скачает '
          'v${provider.latestPublishedVersion ?? '…'} с сайта и перезагрузится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const TrText('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const TrText('Обновить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final message = await provider.sendOtaCommand();
    if (context.mounted) _showSnack(context, message);
  }

  Widget _buildWiFiSection(
      BuildContext context, DeviceConfigProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrText(
          'Подключение к Wi-Fi',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.cardDecoration(
              darkMode: Theme.of(context).brightness == Brightness.dark),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: !provider.isConnected
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WifiScreen(
                                title: 'Wi-Fi (USB)',
                                transport: SerialWifiTransport(provider.serial),
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.wifi_find, size: 18),
                  label: const TrText('Список сетей и сканирование'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ssidController,
                decoration: InputDecoration(
                  labelText: 'SSID',
                  prefixIcon: const Icon(Icons.wifi),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.of(context, 'Пароль'),
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _saveWifi(context, provider),
                      icon: const Icon(Icons.save, size: 18),
                      label: const TrText('Сохранить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _restartDevice(context, provider),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const TrText('Перезагрузить'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _clearWifi(context, provider),
                icon: const Icon(Icons.wifi_off, size: 16),
                label: const TrText('Сбросить Wi-Fi'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialsSection(
      BuildContext context, DeviceConfigProvider provider) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrText(
          'MQTT и API',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.cardDecoration(
              darkMode: theme.brightness == Brightness.dark),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _credentialChip('Логин MQTT', provider.mqttUserSet),
                  _credentialChip('Пароль MQTT', provider.mqttPasswordSet),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _mqttUserController,
                autofillHints: const [AutofillHints.username],
                decoration: InputDecoration(
                  labelText: L10n.of(context, 'Пользователь MQTT'),
                  hintText: L10n.of(context, 'по умолчанию: device'),
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mqttPasswordController,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: L10n.of(context, 'Пароль MQTT'),
                  hintText: L10n.of(context, 'пусто — не менять'),
                  prefixIcon: const Icon(Icons.key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TrText(
                'Доступы сохраняются в NVS на устройстве и в приложение не '
                'передаются. Пустые поля остаются без изменений; пароль '
                'вводится заново при каждой смене.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _saveCredentials(context, provider),
                  icon: const Icon(Icons.save, size: 18),
                  label: const TrText('Сохранить доступы'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _credentialChip(String label, bool isSet) {
    final color = isSet ? AppTheme.successColor : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSet ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 14, color: color),
          const SizedBox(width: 6),
          TrText(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildLogsSection(
      BuildContext context, DeviceConfigProvider provider) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TrText(
              'Логи устройства',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: L10n.of(context, 'Обновить'),
              onPressed: () => provider.fetchLogs(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: AppTheme.cardDecoration(
              darkMode: Theme.of(context).brightness == Brightness.dark),
          child: provider.logs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: TrText(
                      'Логи пусты',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: provider.logs.length,
                  itemBuilder: (context, index) {
                    return _buildLogEntry(context, provider.logs[index],
                        settings.logMode, settings.language);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogEntry(
      BuildContext context, LogEntry entry, LogMode mode, String language) {
    final tagColor = switch (entry.tag) {
      'WiFi' => AppTheme.accentColors[2],
      'MQTT' => AppTheme.accentColors[0],
      'Boot' => AppTheme.accentColors[1],
      'Error' => AppTheme.errorColor,
      _ => AppTheme.primaryColor,
    };
    final msg = LogTranslator.display(mode, language, entry.tag, entry.msg);
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

  Future<void> _connect(
      BuildContext context, DeviceConfigProvider provider, String port) async {
    final ok = await provider.connect(port);
    if (!context.mounted) return;
    if (ok) {
      _showSnack(context, 'Подключено к $port');
    } else {
      _showSnack(context, 'Не удалось подключиться к $port');
    }
  }

  Future<void> _disconnect(
      BuildContext context, DeviceConfigProvider provider) async {
    await provider.disconnect();
    if (!context.mounted) return;
    _showSnack(context, 'Отключено');
  }

  Future<void> _saveWifi(
      BuildContext context, DeviceConfigProvider provider) async {
    final ssid = _ssidController.text;
    if (ssid.trim().isEmpty) {
      _showSnack(context, 'Введите SSID');
      return;
    }
    final password = _passwordController.text;
    if (provider.setWifi(ssid, password)) {
      _showSnack(
          context, 'Настройки отправлены. Устройство перезагружается...');
      _ssidController.clear();
      _passwordController.clear();
    } else {
      _showSnack(context, 'Устройство не подключено');
    }
  }

  Future<void> _saveCredentials(
      BuildContext context, DeviceConfigProvider provider) async {
    final user = _mqttUserController.text.trim();
    final password = _mqttPasswordController.text;
    if (user.isEmpty && password.isEmpty) {
      _showSnack(context, 'Заполните хотя бы одно поле');
      return;
    }
    if (!provider.setCredentials(user: user, password: password)) {
      _showSnack(context, 'Устройство не подключено');
      return;
    }
    _mqttUserController.clear();
    _mqttPasswordController.clear();
    _showSnack(context, 'Доступы сохранены. MQTT переподключится.');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!context.mounted) return;
    provider.refreshInfo();
  }

  Future<void> _restartDevice(
      BuildContext context, DeviceConfigProvider provider) async {
    provider.restart();
    if (!context.mounted) return;
    _showSnack(context, 'Команда перезагрузки отправлена');
  }

  Future<void> _clearWifi(
      BuildContext context, DeviceConfigProvider provider) async {
    provider.clearWifi();
    if (!context.mounted) return;
    _showSnack(context, 'Wi-Fi очищен. Устройство перезагружается...');
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: TrText(message), duration: const Duration(seconds: 2)),
    );
  }
}
