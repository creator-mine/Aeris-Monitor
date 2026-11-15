package online.spe4naz.aeris

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The Wi-Fi tab needs the system network picker: the phone has to join
        // the device's setup AP (Aeris-Setup-XXXX) before it can be configured.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aeris/wifi")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiSettings" -> {
                        startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
