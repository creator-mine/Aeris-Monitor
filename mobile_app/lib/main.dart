import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_notifier/local_notifier.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/api/signaling_api.dart';
import 'core/api/api_client.dart';
import 'core/api/mqtt_client.dart';
import 'core/api/ota_api.dart';
import 'models/firmware_version.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/charts/providers/charts_provider.dart';
import 'features/devices/providers/devices_provider.dart';
import 'features/device_config/providers/device_config_provider.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/firmware/providers/firmware_provider.dart';
import 'features/alerts/providers/alerts_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(FirmwareVersionAdapter());

  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await LocalNotifier.instance.setup(appName: 'IoT Modular System');
  }

  final settingsProvider = SettingsProvider();
  final firmwareProvider = FirmwareProvider();

  await Future.wait([
    settingsProvider.init(),
    firmwareProvider.init(),
  ]);

  final signalingApi = SignalingApi(
    baseUrl: '${settingsProvider.apiUrl}/api/v1',
  );

  final apiClient = ApiClient(
    baseUrl: '${settingsProvider.apiUrl}/api/v1',
  );

  final mqttService = MqttService();
  mqttService.connect(
    broker: settingsProvider.mqttBroker,
    port: settingsProvider.mqttPort,
    useWebSocket: settingsProvider.mqttPort == AppConfig.mqttPort,
    username: settingsProvider.mqttUsername,
    password: settingsProvider.mqttPassword,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        Provider.value(value: signalingApi),
        Provider.value(value: apiClient),
        Provider.value(value: mqttService),
        ChangeNotifierProvider(
          create: (_) => DashboardProvider(
            signalingApi: signalingApi,
            mqtt: mqttService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ChartsProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => DevicesProvider(
            signalingApi: signalingApi,
            otaApi: OtaApi(),
            mqtt: mqttService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => DeviceConfigProvider(otaApi: OtaApi()),
        ),
        ChangeNotifierProvider.value(value: firmwareProvider),
        ChangeNotifierProvider(
          create: (_) => AlertsProvider(apiClient: apiClient),
        ),
      ],
      child: const IoTApp(),
    ),
  );
}
