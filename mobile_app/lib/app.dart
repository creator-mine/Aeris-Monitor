import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/i18n/l10n.dart';
import 'shared/theme/app_theme.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/charts/charts_screen.dart';
import 'features/charts/providers/charts_provider.dart';
import 'features/devices/devices_screen.dart';
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

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

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

        Widget scaffold = Scaffold(
          body: _screens[_currentIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
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
