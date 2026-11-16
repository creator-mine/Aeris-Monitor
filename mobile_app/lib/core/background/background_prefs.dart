/// SharedPreferences key for the "Слежу за устройствами" switch.
///
/// Stored by `SettingsProvider` (Настройки) and read by the foreground-service
/// isolate, which cannot see the provider.
const String backgroundMonitorPrefKey = 'background_monitor';
