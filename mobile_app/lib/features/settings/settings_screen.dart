import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'providers/settings_provider.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/theme/app_theme.dart';
import '../../core/api/mqtt_client.dart';
import '../../core/api/signaling_api.dart';
import '../../core/background/background_service.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/config/log_mode.dart';
import '../devices/providers/devices_provider.dart';
import '../alerts/providers/alerts_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import '../device_config/providers/device_config_provider.dart';
import '../firmware/providers/firmware_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Настройки',
      body: Consumer<SettingsProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSection(
                context,
                'Подключение',
                [
                  _buildTextField(
                    context,
                    'API URL',
                    provider.apiUrl,
                    (value) => provider.setApiUrl(value),
                    icon: Icons.link,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'OTA URL (прошивки)',
                    provider.otaUrl,
                    (value) => provider.setOtaUrl(value),
                    icon: Icons.system_update_alt,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'MQTT Брокер',
                    provider.mqttBroker,
                    (value) => provider.setMqttBroker(value),
                    icon: Icons.cloud,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'MQTT Порт',
                    provider.mqttPort.toString(),
                    (value) {
                      final port = int.tryParse(value);
                      if (port != null) {
                        provider.setMqttPort(port);
                      }
                    },
                    icon: Icons.numbers,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'MQTT Логин',
                    provider.mqttUsername,
                    (value) => provider.setMqttUsername(value),
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'MQTT Пароль',
                    provider.mqttPassword,
                    (value) => provider.setMqttPassword(value),
                    icon: Icons.key,
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'Токен записи (API)',
                    provider.signalingToken,
                    (value) {
                      provider.setSignalingToken(value);
                      context.read<SignalingApi>().setToken(value);
                      context.read<ApiClient>().setToken(value);
                    },
                    icon: Icons.key,
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _applyAndReconnect(context, provider),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Применить и переподключиться'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                'Внешний вид',
                [
                  _buildSwitchTile(
                    context,
                    'Тёмная тема',
                    provider.darkMode,
                    (value) => provider.setDarkMode(value),
                    icon: Icons.dark_mode,
                  ),
                  const SizedBox(height: 16),
                  _buildColorThemeSelector(context, provider),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                'Логирование',
                [
                  SegmentedButton<LogMode>(
                    segments: const [
                      ButtonSegment(
                        value: LogMode.standard,
                        label: Text('Стандартный'),
                        icon: Icon(Icons.article_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: LogMode.lightweight,
                        label: Text('Облегчённый'),
                        icon: Icon(Icons.translate, size: 18),
                      ),
                    ],
                    selected: {provider.logMode},
                    onSelectionChanged: (selection) =>
                        provider.setLogMode(selection.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: provider.language,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Язык логов',
                      prefixIcon: const Icon(Icons.language),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ru', child: Text('Русский')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (lang) {
                      if (lang != null) provider.setLanguage(lang);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'В облегчённом режиме известные системные события '
                    'показываются краткими переведёнными фразами.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                'Фон приложения',
                [
                  _buildBackgroundSelector(context, provider),
                ],
              ),
              if (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android) ...[
                const SizedBox(height: 24),
                _buildSection(
                  context,
                  'Фоновая работа',
                  [
                    _buildSwitchTile(
                      context,
                      'Слежу за устройствами',
                      provider.backgroundMonitor,
                      (value) {
                        provider.setBackgroundMonitor(value);
                        if (value) {
                          unawaited(startBackgroundMonitor(force: true));
                        } else {
                          unawaited(stopBackgroundMonitor());
                        }
                      },
                      icon: Icons.notifications_active_outlined,
                    ),
                    Text(
                      'Постоянное уведомление нужно Android, чтобы события '
                      'правил приходили при закрытом приложении. Выключите — '
                      'уведомление исчезнет, фоновый мониторинг остановится.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              _buildSection(
                context,
                'О приложении',
                [
                  _buildInfoTile(
                    context,
                    'Версия',
                    AppConfig.appVersion,
                    icon: Icons.info,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoTile(
                    context,
                    'Разработчик',
                    'Aeris Monitor',
                    icon: Icons.code,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColorThemeSelector(BuildContext context, SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Акцентный цвет',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(AppTheme.accentColors.length, (index) {
            final isSelected = provider.accentColorIndex == index;
            final color = AppTheme.accentColors[index];
            return GestureDetector(
              onTap: () => provider.setAccentColorIndex(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 22)
                    : null,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBackgroundSelector(BuildContext context, SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.backgroundImagePath != null ||
            provider.backgroundImageBytes != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: kIsWeb
                ? Image.memory(
                    provider.backgroundImageBytes!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _brokenImage();
                    },
                  )
                : Image.file(
                    File(provider.backgroundImagePath!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _brokenImage();
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Прозрачность: ${(provider.backgroundOpacity * 100).round()}%',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Expanded(
                child: Slider(
                  value: provider.backgroundOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(provider.backgroundOpacity * 100).round()}%',
                  onChanged: (value) => provider.setBackgroundOpacity(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(context, provider),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Заменить'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => provider.clearBackgroundImage(),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Сбросить'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.image_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'Фон не выбран',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Выберите изображение для фона приложения',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _pickImage(context, provider),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Выбрать изображение'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _applyAndReconnect(
      BuildContext context, SettingsProvider provider) async {
    if (!context.mounted) return;

    // Resolve providers before any await so no BuildContext is used across
    // an async gap.
    final signalingApi = context.read<SignalingApi>();
    final apiClient = context.read<ApiClient>();
    final mqtt = context.read<MqttService>();
    final devicesProvider = context.read<DevicesProvider>();
    final deviceConfigProvider = context.read<DeviceConfigProvider>();
    final alertsProvider = context.read<AlertsProvider>();
    final dashboardProvider = context.read<DashboardProvider>();
    final firmwareProvider = context.read<FirmwareProvider>();
    final messenger = ScaffoldMessenger.of(context);

    // Apply the API base URL + bearer token at runtime (no restart needed).
    final apiUrl =
        '${SettingsProvider.normalizeUrl(provider.apiUrl)}${AppConfig.apiVersion}';
    signalingApi
      ..setBaseUrl(apiUrl)
      ..setToken(provider.signalingToken);
    apiClient
      ..setBaseUrl(apiUrl)
      ..setToken(provider.signalingToken);

    // The background SSE isolate reads api_url/signaling_token only on start,
    // so restart it to pick up a rotated token or a new host immediately.
    unawaited(startBackgroundMonitor(force: true));

    // Reconnect MQTT with the new broker/port/credentials.
    final mqttPort = kIsWeb ? AppConfig.mqttWssPort : provider.mqttPort;
    final ok = await mqtt.reconnect(
      broker: provider.mqttBroker,
      port: mqttPort,
      useWebSocket: kIsWeb ||
          mqttPort == 9001 ||
          mqttPort == AppConfig.mqttWssPort,
      secure: mqttPort == AppConfig.mqttPort ||
          mqttPort == AppConfig.mqttWssPort,
      username: provider.mqttUsername,
      password: provider.mqttPassword,
    );

    // Refresh data from the newly configured endpoints.
    devicesProvider
      ..setOtaBaseUrl(provider.effectiveOtaUrl)
      ..refreshDevices();
    deviceConfigProvider.setOtaBaseUrl(provider.effectiveOtaUrl);
    alertsProvider.loadAlerts();
    dashboardProvider.loadDevices();

    // Point the OTA/firmware checker at the configured host.
    firmwareProvider
      ..setOtaBaseUrl(provider.effectiveOtaUrl)
      ..fetchServerManifest();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Настройки применены, MQTT переподключён' : 'Настройки применены, MQTT не подключился',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context, SettingsProvider provider) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (xFile == null) return;
    if (kIsWeb) {
      final bytes = await xFile.readAsBytes();
      await provider.setBackgroundImageBytes(bytes);
    } else {
      await provider.setBackgroundImagePath(xFile.path);
    }
  }

  Widget _brokenImage() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Файл не найден', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
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
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context,
    String label,
    String value,
    Function(String) onChanged, {
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return _SettingsTextField(
      label: label,
      value: value,
      onChanged: onChanged,
      icon: icon,
      keyboardType: keyboardType,
      obscureText: obscureText,
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    bool value,
    Function(bool) onChanged, {
    required IconData icon,
  }) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: AppTheme.primaryColor),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildInfoTile(
    BuildContext context,
    String title,
    String value, {
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title),
      subtitle: Text(value),
      contentPadding: EdgeInsets.zero,
    );
  }
}

/// Stateful text field that keeps its own controller.
///
/// Creating `TextEditingController(text: value)` directly in build (as the
/// settings screen used to do) resets the caret on every keystroke, because
/// each provider notification rebuilds the field with a fresh controller.
class _SettingsTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscureText;

  const _SettingsTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
  });

  @override
  State<_SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<_SettingsTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _SettingsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect external changes (e.g. URL normalization) only while the field
    // is not being edited, so the user's caret never jumps.
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      onChanged: widget.onChanged,
    );
  }
}
