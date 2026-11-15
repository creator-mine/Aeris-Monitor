#include "provisioning.h"
#include "config.h"
#include "device_secrets.h"
#include "wifi_config.h"
#include "ring_logger.h"
#include "serial_cmd.h"
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>

namespace Provisioning {

namespace {

AsyncWebServer* server = nullptr;
String g_savedSsid = "";

char lastBytes2Hex(uint8_t b) {
    static const char* hex = "0123456789ABCDEF";
    return hex[b & 0x0F];
}

String apName() {
    uint8_t mac[6];
    WiFi.softAPmacAddress(mac);
    char name[32];
    snprintf(name, sizeof(name), "%s-%c%c%c%c",
             "Aeris-Setup",
             lastBytes2Hex(mac[2]), lastBytes2Hex(mac[3]),
             lastBytes2Hex(mac[4]), lastBytes2Hex(mac[5]));
    return String(name);
}

// Minimal embedded config page (no external assets).
const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Aeris Monitor - Wi-Fi Setup</title>
<style>
  body{font-family:system-ui,Arial,sans-serif;background:#0f172a;color:#e2e8f0;
       margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
  .card{background:#1e293b;padding:28px;border-radius:14px;width:100%;max-width:380px;
        box-shadow:0 10px 30px rgba(0,0,0,.4)}
  h1{font-size:20px;margin:0 0 6px;color:#38bdf8}
  p{color:#94a3b8;font-size:14px;margin:0 0 18px}
  label{display:block;font-size:13px;color:#cbd5e1;margin:12px 0 4px}
  input{width:100%;box-sizing:border-box;padding:10px 12px;border-radius:8px;
        border:1px solid #334155;background:#0f172a;color:#e2e8f0;font-size:15px}
  button{width:100%;margin-top:20px;padding:12px;border:0;border-radius:8px;
         background:#0ea5e9;color:#fff;font-size:16px;font-weight:600;cursor:pointer}
  button:hover{background:#0284c7}
  .status{margin-top:16px;font-size:14px;text-align:center;display:none}
  .ok{color:#4ade80}
</style>
</head>
<body>
<div class="card">
  <h1>Aeris Monitor Setup</h1>
  <p>Enter your router (2.4 GHz) credentials. Optionally set the MQTT and API
     credentials; they are stored on the device (NVS), not compiled into the firmware.</p>
  <form id="f">
    <label for="ssid">Wi-Fi SSID</label>
    <input id="ssid" name="ssid" autocomplete="off" required>
    <label for="password">Password</label>
    <input id="password" name="password" type="password" autocomplete="off">
    <label for="mqtt_user">MQTT user (optional)</label>
    <input id="mqtt_user" name="mqtt_user" autocomplete="off" placeholder="main">
    <label for="mqtt_password">MQTT password (blank = keep)</label>
    <input id="mqtt_password" name="mqtt_password" type="password" autocomplete="off">
    <label for="signaling_token">API token (blank = keep)</label>
    <input id="signaling_token" name="signaling_token" type="password" autocomplete="off">
    <button type="submit">Save &amp; Reconnect</button>
  </form>
  <div id="status" class="status"></div>
</div>
<script>
document.getElementById('f').addEventListener('submit', async (e) => {
  e.preventDefault();
  const st = document.getElementById('status');
  st.style.display = 'block';
  st.className = 'status ok';
  st.textContent = 'Saving...';
  const body = JSON.stringify({
    ssid: e.target.ssid.value.trim(),
    password: e.target.password.value,
    mqtt_user: e.target.mqtt_user.value.trim(),
    mqtt_password: e.target.mqtt_password.value,
    signaling_token: e.target.signaling_token.value
  });
  try {
    const r = await fetch('/wifi/save', {
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body
    });
    const j = await r.json();
    if (j.ok) { st.textContent = 'Saved. Rebooting...'; setTimeout(()=>location.reload(), 1500); }
    else throw new Error(j.error||'save failed');
  } catch (err) {
    st.className = 'status';
    st.textContent = 'Error: ' + err.message;
  }
});
</script>
</body>
</html>
)rawliteral";

void handleRoot(AsyncWebServerRequest* request) {
    request->send(200, "text/html", INDEX_HTML);
}

volatile bool g_keepLoop = true;
String g_pendingBody;

// Async body collector: accumulates a JSON body, parses, saves, then finishes.
void handleSaveCollect(AsyncWebServerRequest* request, uint8_t* data, size_t len,
                       size_t index, size_t total) {
    if (g_pendingBody.length() + len <= 1024) {
        g_pendingBody += String((const char*)data, len);
    }

    if (index + len != total) return;  // wait for the full body

    String body = g_pendingBody;
    g_pendingBody = "";

    JsonDocument doc;
    if (deserializeJson(doc, body)) {
        request->send(400, "application/json", "{\"error\":\"bad_json\"}");
        return;
    }

    String ssid = doc["ssid"] | "";
    String password = doc["password"] | "";
    String mqttUser = doc["mqtt_user"] | "";
    String mqttPass = doc["mqtt_password"] | "";
    String token = doc["signaling_token"] | "";
    ssid.trim();
    mqttUser.trim();

    if (ssid.isEmpty()) {
        request->send(400, "application/json", "{\"error\":\"missing_ssid\"}");
        return;
    }

    // Optional credentials: blank fields keep the existing NVS values.
    if (!mqttUser.isEmpty() || !mqttPass.isEmpty() || !token.isEmpty()) {
        if (!DeviceSecrets::save(mqttUser, mqttPass, token)) {
            request->send(500, "application/json", "{\"error\":\"secrets_write_failed\"}");
            return;
        }
        LOG_INFO("Secrets", "Provisioning credentials updated (NVS)");
    }

    if (!WifiConfig::save(ssid.c_str(), password.c_str())) {
        request->send(500, "application/json", "{\"error\":\"nvs_write_failed\"}");
        return;
    }

    g_savedSsid = ssid;
    LOG_INFO("WiFi", "Provisioning saved credentials (ssid=%s)", ssid.c_str());
    request->send(200, "application/json", "{\"ok\":true}");
    g_keepLoop = false;
}

}  // namespace

bool startAndWait() {
    // Reset per-session state: g_keepLoop may still be false / g_savedSsid set
    // from an earlier provisioning session in the same boot (wifi_reconfigure).
    g_keepLoop = true;
    g_savedSsid = "";

    WiFi.mode(WIFI_AP_STA);  // allow STA coexisting with AP

    WiFi.softAP(apName().c_str(),
                PROVISION_AP_PASSWORD[0] ? PROVISION_AP_PASSWORD : nullptr);

    IPAddress ip = WiFi.softAPIP();
    Serial.println("=========================================");
    Serial.println("  Wi-Fi CONFIGURATION MODE (SoftAP)");
    Serial.println("  SSID  : " + apName());
    if (PROVISION_AP_PASSWORD[0]) Serial.println("  Pass  : " + String(PROVISION_AP_PASSWORD));
    Serial.println("  Web   : http://" + ip.toString() + "/");
    Serial.println("  USB   : CMD:info / CMD:wifi_set:SSID:PASS");
    Serial.println("=========================================");
    LOG_INFO("WiFi", "Config mode: AP %s, http://%s", apName().c_str(), ip.toString().c_str());

    server = new AsyncWebServer(HTTP_PORT);
    server->on("/", HTTP_GET, handleRoot);
    server->on("/wifi/save", HTTP_POST,
        [](AsyncWebServerRequest* r) {
            // nothing to do; body is captured in the body callback
        },
        NULL,
        [](AsyncWebServerRequest* r, uint8_t* data, size_t len,
           size_t index, size_t total) {
            handleSaveCollect(r, data, len, index, total);
        }
    );
    server->onNotFound([](AsyncWebServerRequest* r) {
        r->redirect("/");
    });
    server->begin();

    unsigned long start = millis();
    while (g_keepLoop && millis() - start < PROVISION_TIMEOUT_MS) {
        // Keep the USB/serial setup usable while the SoftAP waits for a
        // client: without this, loop() (and thus CMD:*) is blocked for the
        // whole provisioning window and a blank device cannot be configured
        // from the desktop app.
        serialCmdUpdate();
        delay(20);
    }

    server->end();
    delete server;
    server = nullptr;

    return !g_savedSsid.isEmpty();
}

}  // namespace Provisioning