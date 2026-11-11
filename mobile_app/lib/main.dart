import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'core/background/background_service.dart';
import 'core/notifications/notification_service.dart';
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
import 'features/smart_home/providers/smart_home_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(FirmwareVersionAdapter());

  await NotificationService.init();

  final settingsProvider = SettingsProvider();
  await settingsProvider.init();

  final firmwareProvider = FirmwareProvider(
    otaBaseUrl: settingsProvider.effectiveOtaUrl,
  );
  await firmwareProvider.init();

  final signalingApi = SignalingApi(
    baseUrl: '${settingsProvider.apiUrl}/api/v1',
    token: settingsProvider.signalingToken,
  );

  final apiClient = ApiClient(
    baseUrl: '${settingsProvider.apiUrl}/api/v1',
    token: settingsProvider.signalingToken,
  );

  final mqttService = MqttService();
  final mqttPort = kIsWeb ? AppConfig.mqttWssPort : settingsProvider.mqttPort;
  mqttService.connect(
    broker: settingsProvider.mqttBroker,
    port: mqttPort,
    useWebSocket: kIsWeb ||
        mqttPort == 9001 ||
        mqttPort == AppConfig.mqttWssPort,
    secure: mqttPort == AppConfig.mqttPort ||
        mqttPort == AppConfig.mqttWssPort,
    username: settingsProvider.mqttUsername,
    password: settingsProvider.mqttPassword,
  );

  final dashboardProvider = DashboardProvider(
    signalingApi: signalingApi,
    mqtt: mqttService,
  );
  final smartHomeProvider = SmartHomeProvider(
    apiClient: apiClient,
    mqtt: mqttService,
    signalingApi: signalingApi,
  )..start();
  dashboardProvider.onSensorReading = smartHomeProvider.onLanSensorData;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        Provider.value(value: signalingApi),
        Provider.value(value: apiClient),
        Provider.value(value: mqttService),
        ChangeNotifierProvider.value(value: dashboardProvider),
        ChangeNotifierProvider(
          create: (_) => ChartsProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => DevicesProvider(
            signalingApi: signalingApi,
            otaApi: OtaApi(baseUrl: settingsProvider.effectiveOtaUrl),
            mqtt: mqttService,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => DeviceConfigProvider(
            otaApi: OtaApi(baseUrl: settingsProvider.effectiveOtaUrl),
          ),
        ),
        ChangeNotifierProvider.value(value: firmwareProvider),
        ChangeNotifierProvider(
          create: (_) => AlertsProvider(apiClient: apiClient),
        ),
        ChangeNotifierProvider.value(value: smartHomeProvider),
      ],
      child: const IoTApp(),
    ),
  );

  // Keep the connection alive in the background on Android.
  unawaited(startBackgroundMonitor());
}
