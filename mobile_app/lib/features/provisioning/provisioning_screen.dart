import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/provisioning_api.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

/// First-time Wi-Fi setup on a phone.
///
/// A controller without saved credentials starts an open access point
/// (`Aeris-Setup-XXXX`) and serves a setup page on http://192.168.4.1. This
/// screen talks to that endpoint directly, so provisioning works without a
/// browser (and without a USB cable, which phones do not have).
class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key, this.api});

  /// Injectable for tests; defaults to the real device endpoint.
  final ProvisioningApi? api;

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  static const MethodChannel _wifiChannel = MethodChannel('aeris/wifi');

  late final ProvisioningApi _api = widget.api ?? ProvisioningApi();

  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _mqttUserController = TextEditingController();
  final TextEditingController _mqttPasswordController = TextEditingController();

  bool _obscure = true;
  bool _showAdvanced = false;
  bool _checking = false;
  bool? _reachable;
  bool _saving = false;
  bool _saved = false;
  String _savedSsid = '';
  String? _error;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _mqttUserController.dispose();
    _mqttPasswordController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await _api.probe();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _reachable = ok;
    });
  }

  Future<void> _openWifiSettings() async {
    try {
      await _wifiChannel.invokeMethod('openWifiSettings');
    } catch (_) {
      // Not available on this platform/build; the steps above still apply.
    }
  }

  Future<void> _save() async {
    // SSIDs may legally contain leading/trailing spaces. Android hotspots
    // often do; trimming HERE used to save a profile that never matched.
    final ssid = _ssidController.text;
    if (ssid.trim().isEmpty) {
      setState(() => _error = 'Введите имя домашней сети (SSID)');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await _api.save(
      ssid: ssid,
      password: _passwordController.text,
      mqttUser: _mqttUserController.text.trim(),
      mqttPassword: _mqttPasswordController.text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (error == null) {
        _saved = true;
        _savedSsid = ssid;
        _reachable = true;
        _passwordController.clear();
        _mqttPasswordController.clear();
      } else {
        _error = _describe(error);
        if (error == 'no_connection') _reachable = false;
      }
    });
  }

  String _describe(String code) {
    switch (code) {
      case 'missing_ssid':
        return 'Устройство не приняло пустое имя сети.';
      case 'nvs_write_failed':
        return 'Не удалось сохранить данные в памяти устройства.';
      case 'secrets_write_failed':
        return 'Не удалось сохранить MQTT-доступы на устройстве.';
      case 'bad_json':
        return 'Устройство не поняло запрос. Обновите прошивку.';
      case 'no_connection':
        return 'Нет связи с устройством. Проверьте, что телефон подключён '
            'к сети Aeris-Setup-XXXX.';
      default:
        return 'Ошибка устройства: $code';
    }
  }

  void _reset() {
    setState(() {
      _saved = false;
      _savedSsid = '';
      _error = null;
      _reachable = null;
      _ssidController.clear();
      _passwordController.clear();
      _mqttUserController.clear();
      _mqttPasswordController.clear();
    });
    _check();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Wi-Fi',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _saved ? _buildSuccess(context) : _buildForm(context),
      ),
    );
  }

  // ---------------------------------------------------------------- success

  List<Widget> _buildSuccess(BuildContext context) {
    final theme = Theme.of(context);
    return [
      _card(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppTheme.successColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: TrText(
                    'Устройство настроено',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TrText(
              _savedSsid.isEmpty
                  ? 'Параметры сохранены. Устройство перезагружается.'
                  : 'Устройство подключается к сети «$_savedSsid» и '
                      'перезагружается.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const TrText(
              '1. Вернитесь к домашней сети в настройках Wi-Fi телефона.\n'
              '2. Откройте приложение — устройство появится в списке.',
            ),
            const SizedBox(height: 16),
            if (_isAndroid)
              OutlinedButton.icon(
                onPressed: _openWifiSettings,
                icon: const Icon(Icons.wifi, size: 18),
                label: const TrText('Настройки Wi-Fi телефона'),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.add, size: 18),
              label: const TrText('Настроить ещё одно устройство'),
            ),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------- form

  List<Widget> _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return [
      _buildSteps(context),
      const SizedBox(height: 16),
      _card(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, 'Домашний Wi-Fi'),
            const SizedBox(height: 12),
            TextField(
              controller: _ssidController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: L10n.of(context, 'Имя сети (SSID)'),
                prefixIcon: const Icon(Icons.wifi),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: L10n.of(context, 'Пароль'),
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            TrText(
              'Устройство работает в диапазоне 2,4 ГГц.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _buildAdvanced(context),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save, size: 18),
        label: TrText(_saving ? 'Сохранение...' : 'Сохранить и перезагрузить'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        TrText(
          _error!,
          style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
        ),
      ],
    ];
  }

  Widget _buildSteps(BuildContext context) {
    final theme = Theme.of(context);
    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle(context, 'Первичное подключение')),
              IconButton(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: L10n.of(context, 'Проверить связь с устройством'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _step(
              context,
              1,
              'В настройках Wi-Fi телефона выберите сеть Aeris-Setup-XXXX '
              '(открытая, без пароля).'),
          _step(context, 2,
              'Вернитесь в приложение — оно проверит связь с устройством.'),
          _step(context, 3, 'Введите имя и пароль домашней сети и сохраните.'),
          const SizedBox(height: 12),
          _buildStatusChip(context),
          if (_isAndroid) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openWifiSettings,
              icon: const Icon(Icons.wifi, size: 18),
              label: const TrText('Открыть настройки Wi-Fi'),
            ),
          ],
          const SizedBox(height: 8),
          TrText(
            'Точка доступа устройства работает около 5 минут и поднимается '
            'снова после каждой перезагрузки без сохранённой сети.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    final theme = Theme.of(context);
    if (_checking) {
      return TrText(
        'Проверяю связь с 192.168.4.1...',
        style: theme.textTheme.bodySmall,
      );
    }
    final ok = _reachable;
    if (ok == null) return const SizedBox.shrink();
    final color = ok ? AppTheme.successColor : AppTheme.warningColor;
    return Row(
      children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline,
            size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: TrText(
            ok
                ? 'Устройство найдено (192.168.4.1)'
                : 'Устройство не найдено — телефон не в сети Aeris-Setup-XXXX',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildAdvanced(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final palette = AppPalette.of(context);
    return Container(
      decoration: AppTheme.cardDecoration(darkMode: dark),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: palette.surface,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _showAdvanced,
            onExpansionChanged: (v) => setState(() => _showAdvanced = v),
            leading: const Icon(Icons.key),
            title: const TrText('MQTT (необязательно)'),
            subtitle: const TrText(
              'Пустые поля оставляют текущие значения устройства',
              style: TextStyle(fontSize: 11),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              TextField(
                controller: _mqttUserController,
                decoration: InputDecoration(
                  labelText: L10n.of(context, 'Пользователь MQTT'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mqttPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: L10n.of(context, 'Пароль MQTT'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- helpers

  Widget _card(BuildContext context, Widget child) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: AppTheme.cardDecoration(darkMode: dark),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return TrText(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
    );
  }

  Widget _step(BuildContext context, int number, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: TrText(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: TrText(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
