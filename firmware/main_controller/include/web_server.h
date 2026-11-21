#ifndef WEB_SERVER_H
#define WEB_SERVER_H

#include <Arduino.h>
#include <ESPAsyncWebServer.h>

class WebServer {
public:
    static WebServer& instance();

    void begin(uint16_t httpPort, uint16_t wsPort);
    void broadcastSensors();
    void broadcastStatus();
    void update();

    /// SD-card state as a JSON object. Shared by `/api/v1/sd/info`,
    /// `/api/v1/status` and the MQTT status payload.
    static String buildSdInfoJson();

private:
    WebServer() = default;
    ~WebServer();
    WebServer(const WebServer&) = delete;
    WebServer& operator=(const WebServer&) = delete;

    AsyncWebServer* _http = nullptr;
    AsyncWebSocket* _ws = nullptr;
    uint16_t _wsPort = 81;

    void setupRoutes();
    void setupWebSocket();
    static String buildStatusJson();
    static String buildSensorsJsonValue();
    static String buildHistoryJson(AsyncWebServerRequest* request);

    static void handleSensors(AsyncWebServerRequest* request);
    static void handleStatus(AsyncWebServerRequest* request);
    static void handleData(AsyncWebServerRequest* request);
    static void handleModules(AsyncWebServerRequest* request);
    static void handleSdInfo(AsyncWebServerRequest* request);
    static void handleWifi(AsyncWebServerRequest* request);
    static void handleWifiScan(AsyncWebServerRequest* request);
    static void handleHistory(AsyncWebServerRequest* request);
    static void handleLogs(AsyncWebServerRequest* request);
    static void handleCommand(AsyncWebServerRequest* request);
};

#endif