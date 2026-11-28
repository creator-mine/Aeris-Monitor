#include "web_server.h"
#include "config.h"
#include "mqtt_config.h"
#include "relay_control.h"
#include "ota_updater.h"
#include "ring_logger.h"
#include "wifi_config.h"
#include "wifi_profiles.h"
#include "wifi_manager.h"
#include "network_state.h"
#include "sensor_registry.h"
#include "time_util.h"
#include "sys_info.h"
#include "status_led.h"
#include <WiFi.h>
#include <SD.h>
#include <ArduinoJson.h>
#include <esp_task_wdt.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <algorithm>
#include <cmath>
#include <cstring>
#include <time.h>
#include <vector>

// Set by sdInit() in main.cpp only after the filesystem has actually mounted.
// SD.cardType() can already report a card while SD.begin() failed (for example
// on an exFAT card), so the API must not treat card detection as a mount.
extern bool sdMounted;

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
        request->send(200, "text/plain", "Aeris Monitor - API at " API_PREFIX);
    });

    _http->on(API_PREFIX "/sensors/history", HTTP_GET, handleHistory);
    _http->on(API_PREFIX "/sensors", HTTP_GET, handleSensors);
    _http->on(API_PREFIX "/status", HTTP_GET, handleStatus);
    _http->on(API_PREFIX "/data", HTTP_GET, handleData);
    _http->on(API_PREFIX "/modules", HTTP_GET, handleModules);
    _http->on(API_PREFIX "/sd/info", HTTP_GET, handleSdInfo);
    // Register the more specific route first: ESPAsyncWebServer matches by
    // URI prefix, so "/wifi" would otherwise swallow "/wifi/scan".
    _http->on(API_PREFIX "/wifi/scan", HTTP_GET, handleWifiScan);
    _http->on(API_PREFIX "/wifi", HTTP_GET, handleWifi);
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
                        SensorRegistry::instance().forceRead();
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
                    } else if (strcmp(command, "ota_rollback") == 0) {
                        if (OtaUpdater::rollback()) {
                            client->text("{\"type\":\"ack\",\"command\":\"ota_rollback\",\"status\":\"started\"}");
                        } else {
                            client->text("{\"type\":\"error\",\"error\":\"rollback_failed\"}");
                        }
                    } else if (strcmp(command, "relay") == 0 ||
                               strncmp(command, "relay:", 6) == 0) {
                        const char* state = doc["state"] | "";
                        if (strncmp(command, "relay:", 6) == 0) state = command + 6;
                        if (RelayControl::handleCommand("relay", state)) {
                            client->text(String("{\"type\":\"ack\",\"command\":\"relay\",\"relay\":") +
                                         RelayControl::toJson() + "}");
                        } else {
                            client->text("{\"type\":\"error\",\"error\":\"bad_relay_state\"}");
                        }
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
    json += "\"wifi_connected\":" + String(NetworkState::wifiUp() ? "true" : "false") + ",";
    json += "\"network\":\"" + NetworkState::type() + "\",";
    json += "\"network_connected\":" + String(NetworkState::connected() ? "true" : "false") + ",";
    json += "\"ethernet_link\":" + String(NetworkState::ethernetLink() ? "true" : "false") + ",";
    json += "\"ethernet_speed\":" + String((unsigned)NetworkState::ethernetSpeed()) + ",";
    json += "\"ethernet_ip\":\"" + NetworkState::ethernetIp() + "\",";
    json += "\"ip\":\"" + NetworkState::localIP() + "\",";
    json += "\"time_synced\":" + String(timeSynced() ? "true" : "false") + ",";
    json += "\"rssi\":" + String(NetworkState::rssi()) + ",";
    float chipTemp = chipTemperatureCelsius();
    if (!std::isnan(chipTemp)) {
        json += "\"chip_temp\":" + String(chipTemp, 1) + ",";
    }
    json += "\"firmware\":\"" + String(FIRMWARE_VERSION) + "\",";
    json += "\"led\":\"" + String(StatusLed::stateName()) + "\",";
    json += "\"wifi_ssid\":\"" + NetworkState::ssid() + "\",";
    json += "\"wifi_profiles\":" + String((unsigned)WifiProfiles::count()) + ",";
    json += "\"sd\":" + buildSdInfoJson();
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

void WebServer::handleData(AsyncWebServerRequest* request) {
    String json = "{\"ok\":true,\"status\":" + buildStatusJson() +
                  ",\"sensors\":" + buildSensorsJsonValue() +
                  ",\"modules\":" + SensorRegistry::instance().modulesToJson() + "}";
    request->send(200, "application/json", json);
}

void WebServer::handleModules(AsyncWebServerRequest* request) {
    request->send(200, "application/json", SensorRegistry::instance().modulesToJson());
}

void WebServer::handleSdInfo(AsyncWebServerRequest* request) {
    request->send(200, "application/json", buildSdInfoJson());
}

String WebServer::buildSdInfoJson() {
    const bool cardDetected = SD.cardType() != CARD_NONE;
    const char* cardType = (SD.cardType() == CARD_SDHC) ? "SDHC" : "SD";

    // One field carries the overall state so clients do not have to guess:
    //   ok           - card is present and the filesystem is mounted
    //   mount_failed - card answers, but SD.begin() failed (exFAT/damaged)
    //   no_card      - no card detected at all
    String json = "{\"status\":\"";
    json += sdMounted ? "ok" : (cardDetected ? "mount_failed" : "no_card");
    json += "\",\"mounted\":";
    json += sdMounted ? "true" : "false";
    json += ",\"card_detected\":";
    json += cardDetected ? "true" : "false";

    // While a card is present but the filesystem is unsupported (exFAT) or
    // damaged, SD.begin() fails yet cardType()/totalBytes() still answer.
    // Report that separately so "mounted" no longer looks healthy.
    if (cardDetected) {
        json += ",\"card_type\":\"";
        json += cardType;
        json += "\",\"card_bytes\":" + String(SD.totalBytes());
    }
    if (sdMounted) {
        const uint64_t total = SD.totalBytes();
        const uint64_t used = SD.usedBytes();
        const uint64_t freeBytes = used < total ? total - used : 0;
        const uint32_t usedPct =
            total > 0 ? (uint32_t)((used * 100ULL) / total) : 0;
        json += ",\"type\":\"";
        json += cardType;
        json += "\",\"total_bytes\":" + String(total);
        json += ",\"used_bytes\":" + String(used);
        json += ",\"free_bytes\":" + String(freeBytes);
        json += ",\"used_pct\":" + String(usedPct);
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
    uint16_t maxPoints = 0;
    if (request != nullptr && request->hasParam("max_points")) {
        maxPoints = (uint16_t)request->getParam("max_points")->value().toInt();
    }
    return buildHistoryJsonFor(filterType, since, limit, false, maxPoints);
}

String WebServer::buildHistoryJsonFor(const String& filterType, uint64_t since,
                                      uint16_t limit, bool resetWatchdog,
                                      uint16_t maxPoints) {
    if (limit == 0) limit = HISTORY_MAX_POINTS;
    if (limit > HISTORY_MAX_POINTS) limit = HISTORY_MAX_POINTS;
    if (maxPoints > HISTORY_MAX_BUCKETS) maxPoints = HISTORY_MAX_BUCKETS;
    if (maxPoints > 0 && maxPoints < 2) maxPoints = 2;
    (void)resetWatchdog;  // the async_tcp task is TWDT-subscribed itself

    // Aggregated mode: scan the requested time span and average samples into
    // at most maxPoints time buckets. That keeps the X axis honest for 1h/24h
    // and long ranges instead of returning only the newest `limit` samples.
    struct Bucket {
        uint64_t tsSum;
        double sum;
        uint16_t count;
    };
    static Bucket buckets[HISTORY_MAX_BUCKETS];
    uint16_t bucketCount = 0;
    uint64_t bucketSpan = 0;
    uint64_t nowTs = (uint64_t)time(nullptr) * 1000ULL;
    bool aggregating = maxPoints > 0 && since > 0 && nowTs > since;
    const bool forwardScan = aggregating;
    if (aggregating) {
        bucketCount = maxPoints;
        bucketSpan = nowTs - since;
        for (uint16_t i = 0; i < bucketCount; i++) {
            buckets[i].tsSum = 0;
            buckets[i].sum = 0;
            buckets[i].count = 0;
        }
    }

    // HTTP (async_tcp) and the MQTT callback (loop task) can both request
    // history. Serialize them so the shared point buffer is never interleaved.
    static SemaphoreHandle_t historyLock = nullptr;
    if (historyLock == nullptr) historyLock = xSemaphoreCreateMutex();
    if (historyLock != nullptr) xSemaphoreTake(historyLock, portMAX_DELAY);

    // Parse CSV: timestamp,key,value,unit. Points are collected newest-first
    // and then reversed, so charts always get the freshest data even when the
    // card holds days of 5-second samples.
    struct Point {
        uint64_t ts;
        float value;
    };
    static Point points[HISTORY_MAX_POINTS];  // keep off the task stack (BSS)
    uint16_t count = 0;
    uint16_t parseOps = 0;
    bool stopAll = false;
    uint32_t scannedLines = 0;
    uint32_t matchedLines = 0;
    uint64_t bytesRead = 0;

    // Collect log files: legacy flat file (pre-NTP-sync) + daily-rotated files.
    struct LogFile {
        char name[40];
        time_t mtime;
    };
    // Keep the file list in BSS: the history handler runs on the async_tcp
    // task (8 KB stack), so a 2 KB stack array here risks a stack overflow
    // during long scans.
    static LogFile files[32];
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
        while (df && fileCount < 32) {
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

        // Sort descending by mtime: newest file first, so a bounded scan
        // reaches recent samples instead of spending the budget on old ones.
        for (int i = 0; i < fileCount - 1; i++) {
            for (int j = i + 1; j < fileCount; j++) {
                if (files[j].mtime > files[i].mtime) {
                    LogFile t = files[i];
                    files[i] = files[j];
                    files[j] = t;
                }
            }
        }
    }

    auto parseLine = [&](const char* s) {
        if (stopAll) return;
        if (!aggregating && count >= 1024) return;
        scannedLines++;
        // Parsing a full history is CPU-bound and runs in the async_tcp task.
        // That task is itself subscribed to TWDT, so it must feed the watchdog
        // explicitly: yielding alone is not enough.
        if (++parseOps >= 128) {
            parseOps = 0;
            esp_task_wdt_reset();
            delay(1);
        }

        // Parse directly from the C string: per-line String::substring/toFloat
        // allocations made a month-long scan CPU-bound for ~45 s.
        const char* c1 = strchr(s, ',');
        if (c1 == nullptr) return;
        const char* c2 = strchr(c1 + 1, ',');
        if (c2 == nullptr) return;

        if (!filterType.isEmpty()) {
            const size_t keyLen = (size_t)(c2 - (c1 + 1));
            if (keyLen != filterType.length() ||
                strncmp(c1 + 1, filterType.c_str(), keyLen) != 0) {
                return;
            }
        }

        uint64_t ts = strtoull(s, nullptr, 10);
        if (ts == 0) return;  // pre-NTP sample, not placeable on a timeline
        if (since != 0 && ts < since) {
            // Newest-first scans can stop at the first old line. Aggregated
            // scans go forward through each daily file, so they skip instead.
            if (forwardScan) return;
            stopAll = true;
            return;
        }

        const float value = (float)strtod(c2 + 1, nullptr);
        matchedLines++;
        if (aggregating) {
            uint64_t rel = ts > since ? ts - since : 0;
            uint32_t idx = (uint32_t)((rel * bucketCount) / bucketSpan);
            if (idx >= bucketCount) idx = bucketCount - 1;
            buckets[idx].tsSum += ts;
            buckets[idx].sum += value;
            buckets[idx].count++;
            return;
        }
        if (count >= HISTORY_MAX_POINTS) return;
        points[count].ts = ts;
        points[count].value = value;
        count++;
    };

    // Larger reads drastically reduce SD seek/read overhead for month-long
    // aggregated ranges. The static buffer lives in BSS, not on the stack.
    const size_t CHUNK = HISTORY_READ_CHUNK;
    // Standard (non-aggregated) requests only need the newest samples: ~384 KB
    // is enough for >1000 points even with several metrics per timestamp.
    const int maxChunks = 24;
    static uint8_t buf[CHUNK];
    int chunksRead = 0;

    if (aggregating) {
        // On-demand aggregation reads the card directly. Everything is parsed
        // in place (no per-line String copies), which was the main cost in the
        // first version. Two strategies:
        //   * short ranges: seek near `since` and read that window linearly;
        //   * long ranges: read the newest daily files sequentially until the
        //     byte budget runs out (coverage is reported as `partial`).
        const uint64_t SCAN_BUDGET =
            (bucketSpan > 24ULL * 60ULL * 60ULL * 1000ULL)
                ? 4ULL * 1024ULL * 1024ULL
                : 2ULL * 1024ULL * 1024ULL;
        const bool longRange =
            bucketSpan > 6ULL * 60ULL * 60ULL * 1000ULL;

        auto processChunk = [&](uint8_t* data, int n, String& tail) {
            int start = 0;
            if (!tail.isEmpty()) {
                int nl = -1;
                for (int p = 0; p < n; p++) {
                    if (data[p] == '\n') {
                        nl = p;
                        break;
                    }
                }
                if (nl < 0) {
                    tail += String((const char*)data, (unsigned)n);
                    if (tail.length() > 1024) tail = "";
                    return;
                }
                String line = tail;
                line += String((const char*)data, (unsigned)nl);
                tail = "";
                line.trim();
                if (!line.isEmpty()) parseLine(line.c_str());
                start = nl + 1;
            }
            for (int p = start; p < n; p++) {
                if (data[p] != '\n') continue;
                data[p] = '\0';
                if (p > start) {
                    parseLine((const char*)&data[start]);
                }
                start = p + 1;
            }
            if (start < n) {
                tail = String((const char*)&data[start], (unsigned)(n - start));
            }
        };

        for (int fi = 0; fi < fileCount && !stopAll && bytesRead < SCAN_BUDGET;
             fi++) {
            // For a short window, a file whose last write predates it cannot
            // contribute anything.
            if (!longRange &&
                (uint64_t)files[fi].mtime * 1000ULL < since) {
                continue;
            }
            String path = (files[fi].name[0] == '/')
                              ? String(files[fi].name)
                              : String("/") + files[fi].name;
            File f = SD.open(path, FILE_READ);
            if (!f) continue;
            const uint64_t size = f.size();
            if (size == 0 || size > 0x7FFFFFFFULL) {
                f.close();
                continue;
            }

            uint64_t startOff = 0;
            if (!longRange && since != 0) {
                // Binary search on byte offsets for the first line whose
                // timestamp is >= `since`. A linear bytes-per-time estimate
                // overshot badly when the sampling density varied, cutting
                // 15-50% off the start of the requested window.
                uint64_t lo = 0;
                uint64_t hi = size;
                while (hi - lo > 2048) {
                    const uint64_t mid = lo + (hi - lo) / 2;
                    if (!f.seek((uint32_t)mid)) break;
                    int n = f.read(buf, 200);
                    int nl = -1;
                    for (int p = 0; p < n; p++) {
                        if (buf[p] == '\n') {
                            nl = p;
                            break;
                        }
                    }
                    if (nl < 0 || nl + 1 >= n) {
                        hi = mid;
                        continue;
                    }
                    char head[32];
                    int c = 0;
                    for (int p = nl + 1; p < n && c < 31 && buf[p] != ',';
                         p++) {
                        head[c++] = (char)buf[p];
                    }
                    head[c] = '\0';
                    const uint64_t ts = strtoull(head, nullptr, 10);
                    if (ts == 0 || ts >= since) {
                        hi = mid;
                    } else {
                        lo = mid + 1;
                    }
                }
                startOff = lo;
                if (startOff > 0) {
                    if (!f.seek((uint32_t)startOff)) {
                        f.close();
                        continue;
                    }
                    int n = f.read(buf, 200);
                    int nl = -1;
                    for (int p = 0; p < n; p++) {
                        if (buf[p] == '\n') {
                            nl = p;
                            break;
                        }
                    }
                    if (nl < 0) {
                        f.close();
                        continue;
                    }
                    if (!f.seek((uint32_t)(startOff + (uint64_t)nl + 1))) {
                        f.close();
                        continue;
                    }
                }
            }

            String tail;
            while (!stopAll && bytesRead < SCAN_BUDGET) {
                int n = f.read(buf, CHUNK);
                if (n <= 0) break;
                bytesRead += (uint64_t)n;
                processChunk(buf, n, tail);
                esp_task_wdt_reset();
                delay(1);
            }
            if (!tail.isEmpty()) {
                tail.trim();
                if (!tail.isEmpty()) parseLine(tail.c_str());
            }
            f.close();
        }
    } else {
        // Standard queries read backwards: newest samples first, so a bounded
        // scan budget is spent on the part of the history the caller wants.
        for (int fi = 0; fi < fileCount && !stopAll && count < 1024; fi++) {
            String path = (files[fi].name[0] == '/')
                              ? String(files[fi].name)
                              : String("/") + files[fi].name;
            File f = SD.open(path, FILE_READ);
            if (!f) continue;

            uint64_t pos = f.size();
            String carry;

            while (pos > 0 && !stopAll && count < 1024 &&
                   chunksRead < maxChunks) {
                uint64_t startPos = (pos > CHUNK) ? pos - CHUNK : 0;
                size_t want = (size_t)(pos - startPos);

                bool headComplete = (startPos == 0);
                if (!headComplete) {
                    uint8_t prev = 0;
                    if (f.seek((uint32_t)(startPos - 1)) &&
                        f.read(&prev, 1) == 1 && prev == '\n') {
                        headComplete = true;
                    }
                }

                if (!f.seek((uint32_t)startPos)) break;
                int n = f.read(buf, want);
                if (n <= 0) break;
                chunksRead++;
                if ((chunksRead & 0x03) == 0) {
                    esp_task_wdt_reset();
                    delay(1);
                }
                pos = startPos;

                String chunk((const char*)buf, (unsigned)n);
                if (!carry.isEmpty()) chunk += carry;
                carry = "";

                int end = chunk.length();
                while (end > 0 && !stopAll && count < 1024) {
                    int nl = chunk.lastIndexOf('\n', end - 1);
                    if (nl < 0) break;
                    String line = chunk.substring(nl + 1, end);
                    end = nl;
                    line.trim();
                    if (!line.isEmpty()) parseLine(line.c_str());
                }

                String head = chunk.substring(0, end);
                if (headComplete) {
                    head.trim();
                    if (!head.isEmpty()) parseLine(head.c_str());
                } else {
                    carry = head;
                }
            }
            f.close();
        }
    }

    if (aggregating) {
        String json = "{\"points\":[";
        bool first = true;
        uint64_t firstTs = 0;
        uint64_t lastTs = 0;
        for (uint16_t i = 0; i < bucketCount; i++) {
            if (buckets[i].count == 0) continue;
            if (!first) json += ",";
            first = false;
            const uint64_t ts = buckets[i].tsSum / buckets[i].count;
            const double value = buckets[i].sum / buckets[i].count;
            if (firstTs == 0) firstTs = ts;
            lastTs = ts;
            json += "{\"timestamp\":" + String(ts) + ",";
            json += "\"value\":" + String(value, 2) + "}";
        }
        // Coverage metadata: the client can show "данные с ..." when the card
        // does not reach back to the requested start. A couple of empty
        // buckets at the edge are normal (sparse logging), so require a
        // meaningful gap before calling the result partial.
        const uint64_t bucketMs = bucketCount > 0 ? bucketSpan / bucketCount : 0;
        const uint64_t tolerance =
            std::max<uint64_t>(bucketMs * 2ULL, bucketSpan / 20ULL);
        const bool partial =
            firstTs == 0 || firstTs > since + tolerance;
        json += "],\"covered_since\":" + String(firstTs);
        json += ",\"covered_until\":" + String(lastTs);
        json += ",\"partial\":";
        json += partial ? "true" : "false";
        json += ",\"scanned_bytes\":" + String((unsigned long)bytesRead);
        json += ",\"matched\":" + String((unsigned)matchedLines);
        json += "}";
        Serial.printf("[History] agg type=%s files=%d bytes=%lu matched=%lu "
                      "buckets=%u span=%luh\n",
                      filterType.c_str(), fileCount,
                      (unsigned long)bytesRead, (unsigned long)matchedLines,
                      (unsigned)firstTs, (unsigned long)(bucketSpan / 3600000ULL));
        if (historyLock != nullptr) xSemaphoreGive(historyLock);
        return json;
    }

    // Collected newest-first; expose chronological order to the client.
    for (uint16_t i = 0; i < count / 2; i++) {
        Point t = points[i];
        points[i] = points[count - 1 - i];
        points[count - 1 - i] = t;
    }

    uint16_t n = count < limit ? count : limit;
    uint16_t offset = count > n ? (uint16_t)(count - n) : 0;

    String json = "{\"points\":[";
    for (uint16_t i = 0; i < n; i++) {
        const Point& p = points[offset + i];
        if (i > 0) json += ",";
        json += "{\"timestamp\":" + String((uint64_t)p.ts) + ",";
        json += "\"value\":" + String(p.value, 2) + "}";
    }
    json += "]}";
    if (historyLock != nullptr) xSemaphoreGive(historyLock);
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

void WebServer::handleWifi(AsyncWebServerRequest* request) {
    request->send(200, "application/json", WifiManager::statusJson());
}

void WebServer::handleWifiScan(AsyncWebServerRequest* request) {
    // Start the scan in loop() and answer immediately: a scan can briefly
    // drop the station link, so holding the HTTP request open until it ends
    // makes the client lose the connection. The app polls this endpoint.
    const bool refresh = request->hasParam("refresh");
    if (!WifiManager::scanning() &&
        (refresh || WifiManager::scanAgeMs() > 15000)) {
        WifiManager::requestScan();
    }
    request->send(200, "application/json", WifiManager::scanJson());
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
        SensorRegistry::instance().forceRead();
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
    } else if (strcmp(command, "ota_rollback") == 0) {
        if (OtaUpdater::rollback()) {
            request->send(200, "application/json", "{\"ok\":true,\"command\":\"ota_rollback\",\"status\":\"started\"}");
        } else {
            request->send(500, "application/json", "{\"ok\":false,\"error\":\"rollback_failed\"}");
        }
    } else if (strcmp(command, "relay") == 0 ||
               strncmp(command, "relay:", 6) == 0) {
        const char* state = doc["state"] | "";
        if (strncmp(command, "relay:", 6) == 0) state = command + 6;
        if (RelayControl::handleCommand("relay", state)) {
            request->send(200, "application/json",
                          String("{\"ok\":true,\"relay\":") + RelayControl::toJson() + "}");
        } else {
            request->send(400, "application/json", "{\"error\":\"bad_relay_state\"}");
        }
    } else if (strcmp(command, "wifi_list") == 0) {
        request->send(200, "application/json", WifiManager::statusJson());
    } else if (strcmp(command, "wifi_scan") == 0) {
        WifiManager::requestScan();
        request->send(200, "application/json", WifiManager::scanJson());
    } else if (strcmp(command, "wifi_add") == 0) {
        String ssid = String((const char*)(doc["ssid"] | ""));
        String password = String((const char*)(doc["password"] | ""));
        int priority = doc["priority"] | 0;
        uint8_t id = 0;
        String error;
        if (!WifiProfiles::add(ssid, password, priority, &id, &error)) {
            int code = error == "profiles_full" ? 409 : 400;
            request->send(code, "application/json",
                          String("{\"ok\":false,\"error\":\"") + error + "\"}");
        } else {
            String json = "{\"ok\":true,\"id\":" + String((unsigned)id) + "}";
            request->send(200, "application/json", json);
        }
    } else if (strcmp(command, "wifi_update") == 0) {
        uint8_t id = (uint8_t)(doc["id"] | 0);
        String password = String((const char*)(doc["password"] | ""));
        int priority = doc["priority"] | -1;
        int enabled = doc["enabled"].is<bool>()
                          ? (doc["enabled"].as<bool>() ? 1 : 0)
                          : -1;
        if (!WifiProfiles::update(id, password, priority, enabled)) {
            request->send(404, "application/json", "{\"ok\":false,\"error\":\"not_found\"}");
        } else {
            request->send(200, "application/json", "{\"ok\":true}");
        }
    } else if (strcmp(command, "wifi_remove") == 0) {
        uint8_t id = (uint8_t)(doc["id"] | 0);
        if (!WifiProfiles::remove(id)) {
            request->send(404, "application/json", "{\"ok\":false,\"error\":\"not_found\"}");
        } else {
            request->send(200, "application/json", "{\"ok\":true}");
        }
    } else if (strcmp(command, "wifi_reorder") == 0) {
        std::vector<uint8_t> ids;
        for (JsonVariant v : doc["ids"].as<JsonArray>()) {
            uint8_t id = (uint8_t)(v | 0);
            if (id != 0) ids.push_back(id);
        }
        WifiProfiles::reorder(ids);
        request->send(200, "application/json", "{\"ok\":true}");
    } else if (strcmp(command, "wifi_connect") == 0) {
        uint8_t id = (uint8_t)(doc["id"] | 0);
        String error;
        if (!WifiManager::connectTo(id, &error)) {
            request->send(400, "application/json",
                          String("{\"ok\":false,\"error\":\"") + error + "\"}");
        } else {
            request->send(200, "application/json", "{\"ok\":true}");
        }
    } else if (strcmp(command, "wifi_auto") == 0) {
        WifiManager::setAuto();
        request->send(200, "application/json", "{\"ok\":true}");
    } else if (strcmp(command, "wifi_prepare") == 0) {
        String response = WifiManager::handleRemotePrepare(body);
        request->send(response.indexOf("\"ok\":true") >= 0 ? 200 : 400,
                      "application/json", response);
    } else if (strcmp(command, "wifi_commit") == 0) {
        String response = WifiManager::handleRemoteCommit(body);
        request->send(response.indexOf("\"ok\":true") >= 0 ? 200 : 400,
                      "application/json", response);
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
    if (_ws) {
        _ws->textAll("{\"type\":\"sensor_update\",\"data\":" + buildSensorsJsonValue() + "}");
    }
}

void WebServer::broadcastStatus() {
    if (_ws) {
        _ws->textAll(buildStatusJson());
    }
}

void WebServer::update() {
    if (_ws) {
        _ws->cleanupClients();
    }
}
