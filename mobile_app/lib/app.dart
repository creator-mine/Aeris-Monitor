import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/i18n/l10n.dart';
import 'shared/theme/app_theme.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/settings/providers/update_provider.dart';
import 'features/settings/widgets/updates_section.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/charts/charts_screen.dart';
import 'features/charts/providers/charts_provider.dart';
import 'features/devices/devices_screen.dart';
import 'features/devices/providers/devices_provider.dart';
import 'features/device_config/device_config_screen.dart';
import 'features/provisioning/provisioning_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/firmware/firmware_screen.dart';
import 'features/smart_home/smart_home_screen.dart';

class IoTApp extends StatelessWidget {
  const IoTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'Aeris Monitor',
          debugShowCheckedModeBanner: false,
          locale: Locale(settings.language),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme:
              AppTheme.getTheme(settings.accentColorIndex, settings.darkMode),
          home: const MainNavigation(),
        );
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  /// Periodic tick for [UpdateProvider.maybeAutoCheck]; the provider itself
  /// only hits GitHub when its 4-hour interval has passed.
  Timer? _updateTimer;
  String? _notifiedUpdateVersion;

  /// Presence tick: the registry marks a board offline a few minutes after its
  /// last heartbeat, but without this the app kept the status it saw on load
  /// forever (for example an S3 that was unplugged while the app was open).
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoCheckUpdates());
    _updateTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _autoCheckUpdates(),
    );
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshPresence(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPresence();
  }

  Future<void> _refreshPresence() async {
    if (!mounted) return;
    final dashboard = context.read<DashboardProvider>();
    final devices = context.read<DevicesProvider>();
    await Future.wait([
      dashboard.refreshPresence(),
      devices.refreshPresence(),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    _presenceTimer?.cancel();
    super.dispose();
  }

  /// Silent check for the app's own updates (GitHub Releases) plus a one-time
  /// snackbar when a newer build exists.
  Future<void> _autoCheckUpdates() async {
    final update = context.read<UpdateProvider?>();
    if (update == null || !update.initialized) return;

    await update.maybeAutoCheck();
    if (!mounted) return;

    final release = update.available;
    if (release == null || _notifiedUpdateVersion == release.version) return;
    _notifiedUpdateVersion = release.version;

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '${L10n.of(context, 'Доступно обновление')} ${release.version}',
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: L10n.of(context, 'Открыть'),
          onPressed: () {
            if (mounted) showAppUpdateDialog(context, release);
          },
        ),
      ),
    );
  }

  /// Phones have no USB COM port, so the "Настройка" tab would be dead weight:
  /// it becomes the Wi-Fi provisioning screen instead.
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  List<Widget> get _screens => [
        const DashboardScreen(),
        const ChartsScreen(),
        const DevicesScreen(),
        _isMobile ? const ProvisioningScreen() : const DeviceConfigScreen(),
        const FirmwareScreen(),
        const SettingsScreen(),
        const SmartHomeScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        final hasBackground = kIsWeb
            ? settings.backgroundImageBytes != null
            : settings.backgroundImagePath != null &&
                File(settings.backgroundImagePath!).existsSync();

        final narrow = MediaQuery.sizeOf(context).width < 600;
        final veryNarrow = MediaQuery.sizeOf(context).width < 400;

        Widget scaffold = Scaffold(
          body: _screens[_currentIndex],
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              labelTextStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: veryNarrow ? 10 : 12),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              // Seven destinations do not fit labels on a phone width: only
              // the active tab keeps its caption instead of wrapping every
              // label. A slightly smaller caption also fits "Графики".
              labelBehavior: narrow
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (index) {
                if (index == 1) {
                  final dashboardProvider = context.read<DashboardProvider>();
                  final selectedDevice = dashboardProvider.selectedDevice;
                  if (selectedDevice != null) {
                    context.read<ChartsProvider>().setSelectedDevice(
                          selectedDevice.id,
                          metrics: selectedDevice.allMetrics,
                          device: selectedDevice,
                        );
                  }
                }
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: L10n.of(context, 'Главная'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.show_chart_outlined),
                  selectedIcon: const Icon(Icons.show_chart),
                  label: L10n.of(context, 'Графики'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.devices_other_outlined),
                  selectedIcon: const Icon(Icons.devices_other),
                  label: L10n.of(context, 'Устройства'),
                ),
                NavigationDestination(
                  icon: Icon(_isMobile ? Icons.wifi : Icons.tune),
                  selectedIcon: Icon(_isMobile ? Icons.wifi : Icons.tune),
                  label: _isMobile ? 'Wi-Fi' : L10n.of(context, 'Настройка'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.memory_outlined),
                  selectedIcon: const Icon(Icons.memory),
                  label: L10n.of(context, 'Прошивка'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: L10n.of(context, 'Настройки'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.smart_toy_outlined),
                  selectedIcon: const Icon(Icons.smart_toy),
                  label: L10n.of(context, 'Умный дом'),
                ),
              ],
            ),
          ),
        );

        if (hasBackground) {
          scaffold = Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: settings.backgroundOpacity,
                  child: kIsWeb
                      ? Image.memory(
                          settings.backgroundImageBytes!,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(settings.backgroundImagePath!),
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              scaffold,
            ],
          );
        }

        return scaffold;
      },
    );
  }
}
