import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'shared/theme/app_theme.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/charts/charts_screen.dart';
import 'features/charts/providers/charts_provider.dart';
import 'features/devices/devices_screen.dart';
import 'features/device_config/device_config_screen.dart';
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
          theme: AppTheme.getTheme(settings.accentColorIndex, settings.darkMode),
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

  final List<Widget> _screens = const [
    DashboardScreen(),
    ChartsScreen(),
    DevicesScreen(),
    DeviceConfigScreen(),
    FirmwareScreen(),
    SettingsScreen(),
    SmartHomeScreen(),
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
                final dashboardProvider =
                    context.read<DashboardProvider>();
                final selectedDevice =
                    dashboardProvider.selectedDevice;
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
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Главная',
              ),
              NavigationDestination(
                icon: Icon(Icons.show_chart_outlined),
                selectedIcon: Icon(Icons.show_chart),
                label: 'Графики',
              ),
              NavigationDestination(
                icon: Icon(Icons.devices_other_outlined),
                selectedIcon: Icon(Icons.devices_other),
                label: 'Устройства',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune),
                selectedIcon: Icon(Icons.tune),
                label: 'Настройка',
              ),
              NavigationDestination(
                icon: Icon(Icons.memory_outlined),
                selectedIcon: Icon(Icons.memory),
                label: 'Прошивка',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Настройки',
              ),
              NavigationDestination(
                icon: Icon(Icons.smart_toy_outlined),
                selectedIcon: Icon(Icons.smart_toy),
                label: 'Умный дом',
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
