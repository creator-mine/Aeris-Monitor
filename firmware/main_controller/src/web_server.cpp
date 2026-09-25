#include "web_server.h"
#include "config.h"
#include "mqtt_config.h"
#include "ota_updater.h"
#include "ring_logger.h"
#include "wifi_config.h"
#include "modules/sensor_registry.h"
#include "time_util.h"
#include <WiFi.h>
#include <SD.h>
#include <ArduinoJson.h>

static String lastCommandBody;

WebServer& WebServer::instance() {
    static WebServer server;
    return server;
}

WebServer::~WebServer() {
    delete _ws;
    delete _http;
}

void WebServer::begin(uint16_t httpPort, uint16_t wsPort) {
    _http = new AsyncWebServer(httpPort);
    _ws = new AsyncWebSocket("/ws");
    _wsPort = wsPort;

    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Origin", "*");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    DefaultHeaders::Instance().addHeader("Access-Control-Allow-Headers", "Content-Type");

    setupRoutes();
    setupWebSocket();

    _http->begin();
    Serial.printf("[HTTP] Listening on port %d\n", httpPort);
}

void WebServer::setupRoutes() {
    _http->on("/", HTTP_GET, [](AsyncWebServerRequest* request) {
        request->send(200, "text/plain", "IoT Modular System - API at " API_PREFIX);
    });

    _http->on(API_PREFIX "/sensors", HTTP_GET, handleSensors);
    _http->on(API_PREFIX "/status", HTTP_GET, handleStatus);
    _http->on(API_PREFIX "/modules", HTTP_GET, handleModules);
    _http->on(API_PREFIX "/sd/info", HTTP_GET, handleSdInfo);
    _http->on(API_PREFIX "/sensors/history", HTTP_GET, handleHistory);
    _http->on(API_PREFIX "/logs", HTTP_GET, handleLogs);

    _http->on(API_PREFIX "/command", HTTP_POST,
        [](AsyncWebServerRequest* request) {
            handleCommand(request);
        },
        NULL,
        [](AsyncWebServerRequest* request, uint8_t* data, size_t len,
           size_t index, size_t total) {
            if (index == 0) lastCommandBody = "";
            if (lastCommandBody.length() + len <= 512) {
                lastCommandBody += String((const char*)data, len);
            }
        }
    );

    _http->onNotFound([](AsyncWebServerRequest* request) {
        if (request->method() == HTTP_OPTIONS) {
            request->send(204);
            return;
        }
        request->send(404, "application/json", "{\"error\":\"not_found\"}");
    });
}

void WebServer::setupWebSocket() {
    _ws->onEvent([](AsyncWebSocket* server, AsyncWebSocketClient* client,
                    AwsEventType type, void* arg, uint8_t* data, size_t len) {
        if (type == WS_EVT_CONNECT) {
            Serial.printf("[WS] Client %u connected\n", client->id());
            client->text(buildStatusJson());
            client->text("{\"type\":\"modules_update\",\"modules\":" +
                         SensorRegistry::instance().modulesToJson() + "}");
            client->text("{\"type\":\"sensor_update\",\"data\":" + buildSensorsJsonValue() + "}");
            client->text("{\"type\":\"logs\",\"data\":" + RingLogger::toJson() + "}");
        } else if (type == WS_EVT_DISCONNECT) {
            Serial.printf("[WS] Client %u disconnected\n", client->id());
        } else if (type == WS_EVT_DATA) {
            AwsFrameInfo* info = (AwsFrameInfo*)arg;
            if (info->opcode == WS_TEXT) {
                if (len > 2048) return;  // drop oversized frames (heap guard)
                String msg;
                msg.reserve(len);
                for (size_t i = 0; i < len; i++) msg += (char)data[i];

                JsonDocument doc;
                if (deserializeJson(doc, msg)) return;

                const char* type = doc["type"];
                if (!type) return;

                if (strcmp(type, "request_sensors") == 0) {
                    client->text("{\"type\":\"sensor_update\",\"data\":" +
                                 buildSensorsJsonValue() + "}");
                } else if (strcmp(type, "request_status") == 0) {
                    client->text(buildStatusJson());
                } else if (strcmp(type, "request_history") == 0) {
                    String history = buildHistoryJson(nullptr);
                    client->text("{\"type\":\"history\",\"data\":" + history + "}");
                } else if (strcmp(type, "request_logs") == 0) {
                    client->text("{\"type\":\"logs\",\"data\":" + RingLogger::toJson() + "}");
                } else if (strcmp(type, "command") == 0) {
                    const char* command = doc["command"];
                    if (!command) return;
                    Serial.printf("[WS] Command: %s\n", command);

                    if (strcmp(command, "restart") == 0) {
                        client->text("{\"type\":\"ack\",\"command\":\"restart\"}");
                        delay(100);
                        RingLogger::save();
                        ESP.restart();
                    } else if (strcmp(command, "read_sensor") == 0) {
                        client->text("{\"type\":\"sensor_update\",\"data\":" +
                                     buildSensorsJsonValue() + "}");
                    } else if (strcmp(command, "rescan") == 0) {
                        SensorRegistry::instance().scanI2CBus(I2C_SDA, I2C_SCL);
                        client->text("{\"type\":\"modules_update\",\"modules\":" +
                                     SensorRegistry::instance().modulesToJson() + "}");
                    } else if (strcmp(command, "mqtt_enable") == 0 ||
                               strcmp(command, "mqtt_disable") == 0) {
                        bool on = strcmp(command, "mqtt_enable") == 0;
                        MqttConfig::setEnabled(on);
                        Serial.printf("[MQTT] %s by command\n", on ? "enabled" : "disabled");
                        client->text(String("{\"type\":\"ack\",\"command\":\"") + command +
                                     "\",\"mqtt_enabled\":" + (on ? "true" : "false") + "}");
                    } else if (strcmp(command, "ota") == 0) {
                        bool started = OtaUpdater::request(doc["force"] == true);
                        client->text(started
                            ? "{\"type\":\"ack\",\"command\":\"ota\",\"status\":\"started\"}"
                            : "{\"type\":\"error\",\"error\":\"ota_busy\"}");
                    } else if (strcmp(command, "wifi_set") == 0) {
                        const char* ssid = doc["ssid"];
                        const char* password = doc["password"];
                        if (!ssid || strlen(ssid) == 0) {
                            client->text("{\"type\":\"error\",\"error\":\"missing_ssid\"}");
                        } else if (WifiConfig::save(ssid, password ? password : "")) {
                            LOG_INFO("WiFi", "Credentials saved (ssid=%s), reconnecting", ssid);
                            client->text("{\"type\":\"ack\",\"command\":\"wifi_set\"}");
                            delay(300);
                            RingLogger::save();
                            ESP.restart();
                        } else {
                            client->text("{\"type\":\"error\",\"error\":\"nvs_write_failed\"}");
                        }
                    } else {
                        client->text("{\"type\":\"error\",\"error\":\"unknown_command\"}");
                    }
                }
            }
        }
    });

    _http->addHandler(_ws);
    Serial.printf("[WS] WebSocket at ws://<ip>:%d/ws\n", HTTP_PORT);
}

String WebServer::buildStatusJson() {
    String json = "{";
    json += "\"type\":\"status_update\",";
    json += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
    json += "\"device_name\":\"" + String(DEVICE_NAME) + "\",";
    json += "\"device_type\":\"" + String(DEVICE_TYPE) + "\",";
    json += "\"uptime\":" + String(millis() / 1000) + ",";
    json += "\"free_heap\":" + String(ESP.getFreeHeap()) + ",";
    json += "\"wifi_connected\":" + String(WiFi.status() == WL_CONNECTED ? "true" : "false") + ",";
    json += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
    json += "\"time_synced\":" + String(timeSynced() ? "true" : "false");
    json += ",\"firmware\":\"" + String(FIRMWARE_VERSION) + "\"";
    json += "}";
    return json;
}

String WebServer::buildSensorsJsonValue() {
    return SensorRegistry::instance().sensorsToJson();
}

void WebServer::handleSensors(AsyncWebServerRequest* request) {
    request->send(200, "application/json", buildSensorsJsonValue());
}

void WebServer::handleStatus(AsyncWebServerRequest* request) {
    request->send(200, "application/json", buildStatusJson());
}

void WebServer::handleModules(AsyncWebServerRequest* request) {
    request->send(200, "application/json", SensorRegistry::instance().modulesToJson());
}

void WebServer::handleSdInfo(AsyncWebServerRequest* request) {
    request->send(200, "application/json", buildSdInfoJson());
}

String WebServer::buildSdInfoJson() {
    String json = "{";
    json += "\"mounted\":" + String(SD.cardType() != CARD_NONE ? "true" : "false") + ",";
    if (SD.cardType() != CARD_NONE) {
        json += "\"type\":\"" + String(SD.cardType() == CARD_SDHC ? "SDHC" : "SD") + "\",";
        json += "\"total_bytes\":" + String(SD.totalBytes()) + ",";
        json += "\"used_bytes\":" + String(SD.usedBytes());
    }
    json += "}";
    return json;
}

String WebServer::buildHistoryJson(AsyncWebServerRequest* request) {
    String filterType = "";
    uint64_t since = 0;
    uint16_t limit = 1000;

    if (request != nullptr) {
        if (request->hasParam("type")) filterType = request->getParam("type")->value();
        if (request->hasParam("since")) since = strtoull(request->getParam("since")->value().c_str(), nullptr, 10);
        if (request->hasParam("limit")) limit = (uint16_t)request->getParam("limit")->value().toInt();
    }

    // Parse CSV: timestamp,key,value,unit — keep matching points in a ring buffer.
    struct Point {
        uint64_t ts;
        float value;
    };
    static Point points[1024];  // 20KB — keep off the task stack (BSS)
    uint16_t count = 0, start = 0;

    // Collect log files: legacy flat file (pre-NTP-sync) + daily-rotated files.
    struct LogFile {
        char name[40];
        time_t mtime;
    };
    LogFile files[16];
    int fileCount = 0;

    if (SD.cardType() != CARD_NONE) {
        String legacy = String("/data_") + DEVICE_ID + ".csv";
        if (SD.exists(legacy)) {
            File lf = SD.open(legacy, FILE_READ);
            if (lf) {
                snprintf(files[fileCount].name, sizeof(files[fileCount].name), "%s", legacy.c_str());
                files[fileCount].mtime = lf.getLastWrite();
                fileCount++;
                lf.close();
            }
        }

        String prefix = String("data_") + DEVICE_ID + "_";
        File root = SD.open("/");
        File df = root.openNextFile();
        while (df && fileCount < 16) {
            String name = String(df.name());
            if (name.startsWith(prefix) && name.endsWith(".csv")) {
                snprintf(files[fileCount].name, sizeof(files[fileCount].name), "%s", name.c_str());
                files[fileCount].mtime = df.getLastWrite();
                fileCount++;
            }
            df.close();
            df = root.openNextFile();
        }
        root.close();

        // sort ascending by mtime (oldest first)
        for (int i = 0; i < fileCount - 1; i++) {
            for (int j = i + 1; j < fileCount; j++) {
                if (files[j].mtime < files[i].mtime) {
                    LogFile t = files[i];
                    files[i] = files[j];
                    files[j] = t;
                }
            }
        }
    }

    // Bound total scan time on slow SD cards; 4096 parsed lines is plenty for charts.
    const uint32_t MAX_SCAN = 4096;
    uint32_t scanned = 0;

    for (int fi = 0; fi < fileCount && scanned < MAX_SCAN; fi++) {
        String path = (files[fi].name[0] == '/') ? String(files[fi].name) : String("/") + files[fi].name;
        File f = SD.open(path, FILE_READ);
        if (!f) continue;

        while (f.available() && scanned < MAX_SCAN) {
            String line = f.readStringUntil('\n');
            line.trim();
            if (line.isEmpty()) continue;
            scanned++;

            int c1 = line.indexOf(',');
            if (c1 < 0) continue;
            int c2 = line.indexOf(',', c1 + 1);
            if (c2 < 0) continue;
            int c3 = line.indexOf(',', c2 + 1);
            if (c3 < 0) c3 = line.length();

            String key = line.substring(c1 + 1, c2);
            if (!filterType.isEmpty() && key != filterType) continue;

            uint64_t ts = strtoull(line.substring(0, c1).c_str(), nullptr, 10);
            if (ts < since) continue;

            float value = line.substring(c2 + 1, c3).toFloat();

            if (count < 1024) {
                points[count].ts = ts;
                points[count].value = value;
                count++;
            } else {
                points[start % 1024].ts = ts;
                points[start % 1024].value = value;
                start++;
            }
        }
        f.close();
    }

    uint16_t total = (count < 1024) ? count : 1024;
    uint16_t offset = (count < 1024) ? 0 : start % 1024;
    uint16_t n = total < limit ? total : limit;

    String json = "{\"points\":[";
    for (uint16_t i = 0; i < n; i++) {
        uint16_t idx = (offset + total - n + i) % 1024;
        if (i > 0) json += ",";
        json += "{\"timestamp\":" + String((uint64_t)points[idx].ts) + ",";
        json += "\"value\":" + String(points[idx].value, 2) + "}";
    }
    json += "]}";
    return json;
}

void WebServer::handleHistory(AsyncWebServerRequest* request) {
    request->send(200, "application/json", buildHistoryJson(request));
}

void WebServer::handleLogs(AsyncWebServerRequest* request) {
    uint16_t limit = 0;
    if (request->hasParam("limit")) {
        limit = (uint16_t)request->getParam("limit")->value().toInt();
    }
    request->send(200, "application/json", RingLogger::toJson(limit));
}

void WebServer::handleCommand(AsyncWebServerRequest* request) {
    String body = lastCommandBody;
    lastCommandBody = "";

    if (body.isEmpty()) {
        if (request->hasParam("body", true)) {
            body = request->getParam("body", true)->value();
        } else {
            request->send(400, "application/json", "{\"error\":\"missing_body\"}");
            return;
        }
    }

    JsonDocument doc;
    if (deserializeJson(doc, body)) {
        request->send(400, "application/json", "{\"error\":\"bad_json\"}");
        return;
    }

    const char* command = doc["command"];
    if (!command) {
        request->send(400, "application/json", "{\"error\":\"missing_command\"}");
        return;
    }

    if (strcmp(command, "restart") == 0) {
        request->send(200, "application/json", "{\"ok\":true}");
        delay(100);
        RingLogger::save();
        ESP.restart();
    } else if (strcmp(command, "read_sensor") == 0) {
        request->send(200, "application/json", buildSensorsJsonValue());
    } else if (strcmp(command, "rescan") == 0) {
        SensorRegistry::instance().scanI2CBus(I2C_SDA, I2C_SCL);
        request->send(200, "application/json", SensorRegistry::instance().modulesToJson());
    } else if (strcmp(command, "mqtt_enable") == 0 ||
               strcmp(command, "mqtt_disable") == 0) {
        bool on = strcmp(command, "mqtt_enable") == 0;
        MqttConfig::setEnabled(on);
        Serial.printf("[MQTT] %s by command\n", on ? "enabled" : "disabled");
        String json = "{\"ok\":true,\"command\":\"";
        json += command;
        json += "\",\"mqtt_enabled\":";
        json += on ? "true" : "false";
        json += "}";
        request->send(200, "application/json", json);
    } else if (strcmp(command, "ota") == 0) {
        bool started = OtaUpdater::request(doc["force"] == true);
        if (started) {
            request->send(200, "application/json", "{\"ok\":true,\"command\":\"ota\",\"status\":\"started\"}");
        } else {
            request->send(409, "application/json", "{\"ok\":false,\"error\":\"ota_busy\"}");
        }
    } else if (strcmp(command, "wifi_set") == 0) {
        const char* ssid = doc["ssid"];
        const char* password = doc["password"];
        if (!ssid || strlen(ssid) == 0) {
            request->send(400, "application/json", "{\"error\":\"missing_ssid\"}");
            return;
        }
        if (WifiConfig::save(ssid, password ? password : "")) {
            LOG_INFO("WiFi", "Credentials saved (ssid=%s), reconnecting", ssid);
            request->send(200, "application/json", "{\"ok\":true,\"command\":\"wifi_set\"}");
            delay(300);
            RingLogger::save();
            ESP.restart();
        } else {
            request->send(500, "application/json", "{\"error\":\"nvs_write_failed\"}");
        }
    } else {
        request->send(400, "application/json", "{\"error\":\"unknown_command\"}");
    }
}

void WebServer::broadcastSensors() {
    _ws->textAll("{\"type\":\"sensor_update\",\"data\":" + buildSensorsJsonValue() + "}");
}

void WebServer::broadcastStatus() {
    _ws->textAll(buildStatusJson());
}

void WebServer::update() {
    _ws->cleanupClients();
}
