import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/i18n/l10n.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/tr_text.dart';
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
        final accent = AppTheme.accentColors[settings.accentColorIndex
            .clamp(0, AppTheme.accentColors.length - 1)];
        final palette = settings.darkMode
            ? AppTheme.darkPalette(accent)
            : AppTheme.lightPalette(accent);
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                settings.darkMode ? Brightness.light : Brightness.dark,
            statusBarBrightness:
                settings.darkMode ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: palette.background,
            systemNavigationBarDividerColor: palette.border,
            systemNavigationBarIconBrightness:
                settings.darkMode ? Brightness.light : Brightness.dark,
          ),
        );
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

  void _selectTab(int index) {
    if (index == _currentIndex) return;
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
    setState(() => _currentIndex = index);
  }

  int get _mobileIndex => switch (_currentIndex) {
        0 => 0,
        1 => 1,
        2 => 2,
        6 => 3,
        _ => 4,
      };

  Future<void> _openMoreSheet(BuildContext context) async {
    final palette = AppPalette.of(context);
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: palette.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(_isMobile ? Icons.wifi : Icons.tune),
                  title: TrText(
                    _isMobile ? 'Настройка Wi-Fi' : 'Настройка устройства',
                  ),
                  subtitle: TrText(
                    _isMobile
                        ? 'Подключение платы к сети'
                        : 'COM-порт и параметры платы',
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 3),
                ),
                ListTile(
                  leading: const Icon(Icons.memory_outlined),
                  title: const TrText('Прошивка'),
                  subtitle: const TrText('OTA и локальный .bin'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 4),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const TrText('Настройки'),
                  subtitle: const TrText('Подключение, вид и единицы'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 5),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) _selectTab(selected);
  }

  Widget _buildRail(BuildContext context, bool extended) {
    final palette = AppPalette.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: NavigationRail(
        extended: extended,
        minWidth: 78,
        minExtendedWidth: 240,
        groupAlignment: -0.86,
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        labelType: extended
            ? NavigationRailLabelType.none
            : NavigationRailLabelType.all,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(0, 22, 0, 26),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primary, palette.humidity],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.sensors,
                  color: AppTheme.onAccent(primary),
                  size: 26,
                ),
              ),
              if (extended) ...[
                const SizedBox(height: 12),
                Text(
                  'AERIS',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                Text(
                  'MONITOR',
                  style: TextStyle(
                    color: palette.faint,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: extended
                  ? Text(
                      'v1.3.11',
                      style: TextStyle(color: palette.faint, fontSize: 11),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        destinations: [
          NavigationRailDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: TrText(L10n.of(context, 'Главная')),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.show_chart_outlined),
            selectedIcon: const Icon(Icons.show_chart),
            label: TrText(L10n.of(context, 'Графики')),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.devices_other_outlined),
            selectedIcon: const Icon(Icons.devices_other),
            label: TrText(L10n.of(context, 'Устройства')),
          ),
          NavigationRailDestination(
            icon: Icon(_isMobile ? Icons.wifi : Icons.tune),
            selectedIcon: Icon(_isMobile ? Icons.wifi : Icons.tune),
            label: TrText(
              _isMobile ? 'Настройка Wi-Fi' : L10n.of(context, 'Настройка'),
            ),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.memory_outlined),
            selectedIcon: const Icon(Icons.memory),
            label: TrText(L10n.of(context, 'Прошивка')),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: TrText(L10n.of(context, 'Настройки')),
          ),
          NavigationRailDestination(
            icon: const Icon(Icons.smart_toy_outlined),
            selectedIcon: const Icon(Icons.smart_toy),
            label: TrText(L10n.of(context, 'Умный дом')),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNav(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: NavigationBar(
        backgroundColor: palette.surface,
        selectedIndex: _mobileIndex,
        onDestinationSelected: (index) {
          if (index == 4) {
            _openMoreSheet(context);
          } else {
            _selectTab(const [0, 1, 2, 6][index]);
          }
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
            icon: const Icon(Icons.smart_toy_outlined),
            selectedIcon: const Icon(Icons.smart_toy),
            label: L10n.of(context, 'Умный дом'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: L10n.of(context, 'Ещё'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        final hasBackground = kIsWeb
            ? settings.backgroundImageBytes != null
            : settings.backgroundImagePath != null &&
                File(settings.backgroundImagePath!).existsSync();

        final width = MediaQuery.sizeOf(context).width;
        final useRail = width >= 900;
        final extendedRail = width >= 1240;
        final palette = AppPalette.of(context);

        Widget scaffold = useRail
            ? Scaffold(
                backgroundColor: palette.background,
                body: Row(
                  children: [
                    _buildRail(context, extendedRail),
                    Expanded(
                      child: _LazyIndexedStack(
                        index: _currentIndex,
                        children: _screens,
                      ),
                    ),
                  ],
                ),
              )
            : Scaffold(
                backgroundColor: palette.background,
                body: _LazyIndexedStack(
                  index: _currentIndex,
                  children: _screens,
                ),
                bottomNavigationBar: _buildMobileNav(context),
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

/// Builds a tab the first time it is opened and then keeps it alive offstage,
/// so scroll positions and loaded data survive tab switches without paying for
/// every screen (and its network requests) on cold start.
class _LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _LazyIndexedStack({
    required this.index,
    required this.children,
  });

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late final Set<int> _visited = {widget.index};

  @override
  void didUpdateWidget(covariant _LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: _visited.contains(i)
                  ? widget.children[i]
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}
