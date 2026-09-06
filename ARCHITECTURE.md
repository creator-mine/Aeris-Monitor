# Архитектура децентрализованной модульной IoT-системы

## Текущая проблема

```
ESP32 ──MQTT──► MQTT Broker ──MQTT──► Mobile App
ESP32 ──REST──► REST API  ──REST──► Mobile App
```

Данные проходят через центральные серверы (MQTT Broker + REST API). Если сервер недоступен — система не работает.

## Целевая архитектура

```
                    ┌──────────────────────┐
                    │   Signaling Server   │
                    │  (только реестр)     │
                    │                      │
                    │  Список устройств:   │
                    │  ├ ESP32-1: IP:PORT  │
                    │  ├ ESP32-2: IP:PORT  │
                    │  └ ESP32-3: IP:PORT  │
                    └──────┬───────────┬───┘
                           │           │
              ┌────────────┘           └────────────┐
              │  POST /register                      │  GET /devices
         ┌────▼─────┐                         ┌─────▼──────┐
         │  ESP32-C3 │◄──── WebSocket ───────►│  Клиенты   │
         │           │◄──── HTTP REST ────────│  (Mobile)  │
         │  Сервер   │──── Данные real-time ──►│            │
         │  + SD     │──── История с SD ──────►│            │
         └───────────┘                         └────────────┘
```

### Принципы

1. **ESP32 — полноценный сервер.** Поднимает HTTP REST + WebSocket сервер, отдаёт текущие показания и историю с SD-карты напрямую клиенту.
2. **Signaling Server — только соединяет.** Хранит только список устройств и их IP/порт. Не хранит данные с датчиков.
3. **Прямое соединение (P2P).** Клиент получает от Signaling Server IP устройства и стучится напрямую.
4. **MQTT — опционально.** Может использоваться как локальный транспорт внутри LAN, но не обязателен.
5. **Данные хранятся на устройстве.** SD-карта — основное и единственное постоянное хранилище.

---

## Модульная платформа hot-plug датчиков

Ключевая особенность системы — каждый датчик или исполнительное устройство является **подключаемым модулем**. Система автоматически обнаруживает модули и подгружает нужный драйвер без изменения кода.

```
                          ┌──────────────────────────┐
                          │   Module Registry (ESP32) │
                          │                          │
                          │  I2C Bus Scan ───────────►│
                          │  UART Module Register ───►│
                          │                          │
                          │  Активные модули:        │
                          │  ├ BME680 @ 0x76         │
                          │  ├ BH1750  @ 0x23        │
                          │  └ UART Module #1 (C6)   │
                          └──────────┬───────────────┘
                                     │
                          ┌──────────▼───────────────┐
                          │   Data Bus               │
                          │                          │
                          │  Каждый модуль отдаёт    │
                          │  массив метрик:          │
                          │  [{ key, value, unit }]  │
                          └──────────────────────────┘
```

### 2.1 Интерфейс модуля (firmware)

Все модули реализуют единый интерфейс:

```cpp
class SensorModule {
public:
    virtual ~SensorModule() = default;

    // Уникальный ID типа модуля
    virtual uint8_t typeId() = 0;

    // Название модуля (для диагностики)
    virtual const char* moduleName() = 0;

    // I2C адрес(а), которые модуль сканирует (0 = не I2C)
    virtual std::vector<uint8_t> i2cAddresses() = 0;

    // Проверить присутствие модуля по адресу
    virtual bool detect(uint8_t address) = 0;

    // Инициализация модуля
    virtual bool init(uint8_t address) = 0;

    // Чтение данных — возвращает список метрик
    virtual std::vector<Metric> read() = 0;

    // Список метрик, которые модуль предоставляет
    virtual std::vector<MetricDef> metrics() = 0;

    // Период опроса (мс)
    virtual uint32_t readInterval() = 0;
};

struct Metric {
    const char* key;     // "temperature"
    float       value;   // 25.4
    const char* unit;    // "°C"
};

struct MetricDef {
    const char* key;     // "temperature"
    const char* name;    // "Температура"
    const char* unit;    // "°C"
};
```

### 2.2 Автообнаружение модулей

**На ESP32:** При старте (или по команде `rescan`) Module Registry:

1. Сканирует I2C-шину (адреса 1–127)
2. По каждому найденному адресу перебирает все зарегистрированные драйверы
3. Вызывает `detect(address)` — модуль проверяет chip ID или специфичный регистр
4. При успехе — вызывает `init(address)` и добавляет в активный список
5. Для UART-модулей (ESP32-C6) — регистрация по бинарному протоколу с указанием `typeId`

**Критерии детекта (chip ID):**

| Модуль | I2C адрес | Chip ID регистр | Chip ID значение |
|--------|-----------|-----------------|------------------|
| BME680 | 0x76/0x77 | 0xD0 | 0x61 |
| BH1750 | 0x23/0x5C | — | Адрес + ACK |
| BMP280 | 0x76/0x77 | 0xD0 | 0x58 |
| SHT30 | 0x44/0x45 | — | Адрес + ACK |
| CCS811 | 0x5A/0x5B | 0x20 | 0x81 |
| SGP30 | 0x58 | 0x20 | — |

**Логика обнаружения:**

```
scanI2CBus()
  для каждого адреса 1..127:
    если устройство ответило (Wire.endTransmission() == 0):
      для каждого драйвера в registry:
        если адрес в i2cAddresses драйвера:
          если driver.detect(addr):
            driver.init(addr)
            activeModules.append(driver)
            break

  для каждого активного модуля:
    если модуль больше не отвечает:
      activeModules.remove(module)
      log("[Module] disconnected: " + module.moduleName())
```

### 2.3 Реестр драйверов (Driver Registry)

Модули регистрируются статически при старте прошивки:

```cpp
// sensor_registry.h
class SensorRegistry {
public:
    static SensorRegistry& instance();

    void registerDriver(SensorModule* driver);
    void scanAll();          // полное сканирование I2C
    void readAll();          // опрос всех активных модулей
    void removeInactive();   // удалить пропавшие модули

    std::vector<SensorModule*> activeModules();
    JsonDocument toJson();   // для REST/WS ответа

private:
    std::vector<SensorModule*> _drivers;     // все известные драйверы
    std::vector<SensorModule*> _active;      // обнаруженные модули
    std::map<uint8_t, uint8_t> _addrMap;     // I2C addr → индекс в _active
};
```

**Регистрация драйверов:**

```cpp
// modules/bme680_module.h
class BME680Module : public SensorModule { ... };

// modules/bh1750_module.h
class BH1750Module : public SensorModule { ... };

// setup()
SensorRegistry::instance().registerDriver(new BME680Module());
SensorRegistry::instance().registerDriver(new BH1750Module());
// добавление нового модуля = 1 файл + 1 строка регистрации
// или макрос для авторегистрации
```

**Или ещё проще — макрос авторегистрации:**

```cpp
// modules/bme680_module.cpp
REGISTER_SENSOR(BME680Module);

// modules/bh1750_module.cpp
REGISTER_SENSOR(BH1750Module);
```

Макрос использует статическую инициализацию для автоматической регистрации в `SensorRegistry` без единой правки `setup()`.

### 2.4 UART-протокол для модульных устройств

Текущий протокол (фиксированный 20-байтный пакет с 5 float) заменяется на **динамический**:

**Регистрация модуля (модуль → контроллер):**

```
[0xAA][0x55][module_id][CMD_REGISTER:0x01][len_hi][len_lo]
  [type_id][name_len][name...][metrics_count]
  [metric1_key_len][metric1_key...][metric1_unit_len][metric1_unit...]
  [metric2_key_len][metric2_key...] ...
  [crc_hi][crc_lo]
```

**Пример (BME680):**

```
AA 55 01 01 00 29   -- заголовок: модуль #1, команда REGISTER, длина 41
01                  -- type_id = 0x01 (BME680)
06 42 4D 45 36 38 30 -- name = "BME680" (6 байт)
04                  -- 4 метрики
0B 74 65 6D 70 65 72 61 74 75 72 65 02 43 30   -- temperature, °C
09 68 75 6D 69 64 69 74 79         01 25        -- humidity, %
0A 70 72 65 73 73 75 72 65         03 68 50 61  -- pressure, hPa
0E 67 61 73 5F 72 65 73 69 73 74 61 6E 63 65 04 4F 68 6D -- gas_resistance, Ohm
XX XX               -- CRC-16
```

**Данные от модуля (модуль → контроллер):**

```
[0xAA][0x55][module_id][CMD_SENSOR_DATA:0x03][len_hi][len_lo]
  [timestamp_hi][timestamp_lo]  -- 4 байта, millis()
  [metric1_value_float]         -- 4 байта (IEEE 754)
  [metric2_value_float]         -- 4 байта
  ...
  [crc_hi][crc_lo]
```

Порядок метрик фиксирован для каждого type_id (определён при регистрации).

**Преимущества:**
- Контроллеру не нужно знать формат данных модуля заранее
- Модуль сам сообщает, какие метрики он предоставляет
- Можно добавлять новые типы модулей без обновления контроллера
- Обратная совместимость: старые модули продолжают работать

### 2.5 Hot-plug: добавление/удаление модулей

**I2C-модули:**
- При старте — полное сканирование шины
- Каждые N секунд — проверка всех активных модулей (liveness check)
- Если модуль перестал отвечать → удаляем из активного списка → клиенты видят статус offline
- Если на шине появился новый модуль (например, после перезагрузки) → обнаруживается при liveness check

**UART-модули (ESP32-C6):**
- Модуль шлёт `CMD_REGISTER` при старте
- Модуль шлёт `CMD_HEARTBEAT` каждые 30 секунд
- Если heartbeat пропал на 3 цикла → модуль считается offline
- При появлении нового модуля → регистрация + начало опроса

**Liveness check (каждые 10 секунд):**

```cpp
void checkModules() {
    for (auto& mod : _active) {
        if (mod->isUART()) continue; // UART проверяется heartbeat'ом
        Wire.beginTransmission(mod->address());
        if (Wire.endTransmission() != 0) {
            log("[Module] lost: " + mod->moduleName());
            _deadModules.push(mod);
        }
    }
    for (auto& mod : _deadModules) {
        _active.erase(mod);
    }
    _deadModules.clear();
}
```

### 2.6 REST API — динамический список модулей и метрик

**ESP32 отдаёт модули и их метрики динамически:**

```
GET /api/v1/modules
→ [
    {
        "id": "bme680_0x76",
        "type_id": 1,
        "name": "BME680",
        "status": "online",
        "metrics": [
            { "key": "temperature", "name": "Температура", "unit": "°C" },
            { "key": "humidity",    "name": "Влажность",   "unit": "%" },
            { "key": "pressure",    "name": "Давление",    "unit": "hPa" },
            { "key": "gas_resistance", "name": "Газ",      "unit": "Ohm" }
        ]
    },
    {
        "id": "bh1750_0x23",
        "type_id": 2,
        "name": "BH1750",
        "status": "online",
        "metrics": [
            { "key": "illuminance", "name": "Освещённость", "unit": "lux" }
        ]
    }
]

GET /api/v1/sensors
→ {
    "timestamp": 12345678,
    "modules": {
        "bme680_0x76": {
            "temperature": 25.4,
            "humidity": 55.2,
            "pressure": 1013.2,
            "gas_resistance": 85000
        },
        "bh1750_0x23": {
            "illuminance": 320.0
        }
    }
}
```

### 2.7 Mobile App — динамические метрики

Приложение больше не использует **хардкод** `sensorUnits` и `sensorNames` из `app_config.dart`. Вместо этого:

1. При подключении к устройству получает `GET /api/v1/modules`
2. Строит UI-карточки динамически на основе списка метрик
3. Для каждой метрики использует `key` для маппинга данных, `name` для отображения, `unit` для единиц измерения
4. Если устройство поддерживает новый неизвестный тип датчика — приложение всё равно его отобразит

**Динамический дашборд:**

```dart
class MetricCard extends StatelessWidget {
    final String label;    // из MetricDef.name
    final double value;
    final String unit;    // из MetricDef.unit
    final IconData icon;  // можно мапить key → icon динамически
}

// Вместо:
Map<String, String> sensorUnits = { 'temperature': '°C', ... };

// Теперь:
final modules = await api.getModules(deviceId);
for (final module in modules) {
    for (final metric in module.metrics) {
        dashboard.addCard(MetricCard(
            label: metric.name,
            value: data.modules[module.id][metric.key],
            unit: metric.unit,
        ));
    }
}
```

### 2.8 Добавление нового сенсорного модуля (пример)

Хотим добавить датчик **SCD30 (CO₂)**:

**Шаг 1 — Создать класс драйвера:**

```cpp
// firmware/modules/scd30_module.h
class SCD30Module : public SensorModule {
    uint8_t typeId() override { return 0x03; }
    const char* moduleName() override { return "SCD30"; }
    std::vector<uint8_t> i2cAddresses() override { return {0x61}; }
    bool detect(uint8_t addr) override { /* прочитать chip ID */ }
    bool init(uint8_t addr) override { /* инициализация SCD30 */ }
    std::vector<Metric> read() override { /* CO₂ + T + RH */ }
    std::vector<MetricDef> metrics() override {
        return {
            {"co2", "CO₂", "ppm"},
            {"temperature", "Температура", "°C"},
            {"humidity", "Влажность", "%"}
        };
    }
    uint32_t readInterval() override { return 2000; }
};
```

**Шаг 2 — Зарегистрировать драйвер:**

```cpp
// setup() или через REGISTER_SENSOR макрос
SensorRegistry::instance().registerDriver(new SCD30Module());
```

**Всё.** Система автоматически:
- Найдёт SCD30 на I2C при следующем сканировании
- Начнёт опрашивать и публиковать данные
- Отобразит метрики в мобильном приложении и на веб-сайте
- Без единого изменения в других частях системы

---

## Компоненты системы

### 1. Signaling Server (новый компонент)

Лёгкий сервер для регистрации и обнаружения устройств.

**Стек:** Node.js (Express или Fastify) или Python (FastAPI)

**API:**

```
POST /api/v1/devices/register
  Body: { id, name, type, ip, port, status, sensors[] }
  Response: { success: true }

GET /api/v1/devices
  Response: [{ id, name, type, ip, port, status, lastSeen, sensors[] }]

GET /api/v1/devices/:id
  Response: { id, name, type, ip, port, status, lastSeen, sensors[] }

DELETE /api/v1/devices/:id
  (при отключении устройства)
```

**Хранение:** In-memory (MAP) + опционально SQLite для персистентности.

**Требования:**
- Не хранит данные датчиков
- Простой heartbeat (ESP32 шлёт ping каждые 30 сек, сервер удаляет если 3 минуты тишины)
- Работает без БД (in-memory) — минимальные ресурсы

### 2. ESP32 Firmware (изменения)

Главный контроллер (ESP32-C3) становится сервером.

**Текущее:** `main.cpp` — читает датчики, публикует MQTT, пишет SD.

**Новое:** Добавить HTTP REST + WebSocket сервер.

**Выбор библиотек:**
- `ESPAsyncWebServer` — HTTP сервер
- `WebSockets` — для real-time push клиентам
- `ArduinoJson` — уже есть

**HTTP REST API (на ESP32):**

```
GET  /api/v1/status             → { deviceId, uptime, freeHeap, sensors[], modules[] }
GET  /api/v1/sensors            → { temperature, humidity, pressure, gas, illuminance, timestamp }
GET  /api/v1/sensors/history    → { points: [{ timestamp, values }] }
       ?since=<timestamp>
       &type=<sensor_type>
       &limit=<max_points>
GET  /api/v1/modules            → [{ moduleId, status, lastSeen }]
GET  /api/v1/sd/info            → { mounted, totalBytes, usedBytes, files[] }
POST /api/v1/command            → { command: "restart" | "read_sensor" }
```

**WebSocket API (на ESP32):**

```
Client → Server: { type: "subscribe" }
Server → Client: { type: "sensor_update", data: { temperature, humidity, ... } }
                 (каждые 5 секунд — все подписанным клиентам)

Client → Server: { type: "request_history", params: { since, type, limit } }
Server → Client: { type: "history", data: [...] }

Server → Client: { type: "module_data", moduleId, data: {...} }
Server → Client: { type: "heartbeat" }
Client → Server: { type: "command", command: "restart" }
```

**Логика работы ESP32:**

```
setup()
  WiFi.connect()
  sensorsInit()
  sdInit()
  startWebServer()       ← HTTP :80
  startWebSocketServer() ← WS :81
  registerWithSignaling() ← POST /api/v1/devices/register
  // MQTT — опционально, если включено в конфиге

loop()
  wifiUpdate()
  sensorsRead()          ← каждые 5 сек
  sdSave()               ← каждые 5 сек
  webSocketBroadcast()   ← рассылка подписчикам
  signalingHeartbeat()   ← каждые 30 сек
  mqttUpdate()           ← опционально
  uartUpdate()
```

### 3. Mobile App (изменения)

**Новый провайдер — `DirectConnectionProvider`:**

```
Mobile App
├── ApiClient          → REST к Signaling Server (получение списка устройств)
├── DirectDeviceClient → HTTP/WS напрямую к ESP32
├── MqttService        → остаётся как опциональный fast-path
└── ConnectionManager  → выбирает: прямой канал или relay
```

**Логика подключения к устройству:**

```
1. Получить список устройств с Signaling Server (GET /devices)
2. Выбрать устройство
3. Попробовать прямое подключение:
   a. WebSocket → ws://<device_ip>:81
   b. HTTP → http://<device_ip>:80/api/v1/status
4. Если успех — данные идут напрямую
5. Если неудача — fallback через Relay Server (если настроен)
```

**Изменения в существующих провайдерах:**

- `DashboardProvider` — подписывается на WebSocket ESP32 вместо MQTT
- `ChartsProvider` — получает историю через HTTP с ESP32 (`/history`)
- `DevicesProvider` — получает список через Signaling Server, команды шлёт напрямую на ESP32

### 4. Relay Server (опционально)

Если клиент и ESP32 в разных сетях (NAT), прямое подключение невозможно.

**Решение:** Relay-сервер (на том же хосте, что Signaling Server).

```
Клиент → Relay → ESP32
ESP32  → Relay → Клиент
```

Простой WebSocket-прокси. ESP32 и клиент подключаются к Relay, Relay пересылает данные.

### 5. Веб-сайт (в планах)

Веб-версия дашборда, использующая ту же архитектуру:

```
Браузер ──HTTP/WS──► ESP32 (прямое соединение)
Браузер ──REST────► Signaling Server (список устройств)
```

**Рекомендация:** Одностраничное приложение (SPA) на Vue.js или Svelte без собственного бэкенда. Всё взаимодействие — напрямую с ESP32 или с Signaling Server.

---

## Поток данных (новая архитектура)

### Real-time (текущие показания)

```
ESP32-C3
  ├── BME680 + BH1750 ← I2C (каждые 5 сек)
  ├── SD-карта ← запись CSV (каждые 5 сек)
  ├── WebSocket Server ← Broadcast всем подписанным клиентам
  │
  ├── [LAN] ──WebSocket──► Mobile App / Web (прямое соединение)
  │
  └── [WAN] ──WebSocket──► Relay Server ──WebSocket──► Mobile App / Web
```

### История (запрос данных за период)

```
Mobile App
  └── HTTP GET /api/v1/sensors/history?since=<ts>&type=<type>
       │
       ├── [LAN] ──► ESP32:80 (прямо)
       │
       └── [WAN] ──► Relay Server ──► ESP32 (через relay)
            │
            ESP32 читает SD-карту, отдаёт JSON
```

### Обновление прошивки (без изменений)

```
Mobile App → PlatformIO CLI → COM-порт → ESP32
```
Остаётся как есть — это локальное действие.

---

## Схема перехода (миграция)

### Фаза 0: Модульная платформа датчиков
- [x] Создать абстрактный интерфейс `SensorModule` (typeId, detect, init, read, metrics)
- [x] Создать `SensorRegistry` (singleton, registerDriver, scanAll, readAll)
- [x] Создать макрос `REGISTER_SENSOR` для авторегистрации
- [x] Реализовать I2C-сканирование с chip ID верификацией
- [x] Переписать BME680 как `BME680Module : SensorModule`
- [x] Переписать BH1750 как `BH1750Module : SensorModule`
- [x] Реализовать liveness check (горячее отключение/подключение)
- [x] Обновить UART-протокол на динамический (регистрация с типом/метриками)
- [ ] REST API `/api/v1/modules` — динамический список модулей *(нужен HTTP-сервер — Фаза 1; `modulesToJson()`/`sensorsToJson()` уже готовы)*
- [x] Mobile App — динамические метрики (без хардкода sensorUnits/sensorNames)

### Фаза 1: ESP32 как сервер
- [x] Добавить HTTP-сервер (ESPAsyncWebServer) на ESP32
- [x] Добавить WebSocket-сервер
- [x] Реализовать REST API на ESP32 (статус, сенсоры, история с SD)
- [x] NTP: реальные метки времени для SD-истории и WebSocket push
- [ ] Удалить жёсткую зависимость от MQTT (сделать опцией)

### Фаза 2: Signaling Server
- [x] Создать Node.js сервер (без зависимостей, `server/src/`)
- [x] Endpoint регистрации устройств
- [x] Endpoint списка устройств
- [x] Heartbeat-механизм (JSON-тело, query, или заголовок `X-Device-Id`)
- [x] Автоудаление устаревших устройств (180 сек без heartbeat)
- [x] CORS для будущего веб-клиента
- [x] ESP32 регистрируется при старте + heartbeat каждые 30 сек
- [x] Mock-устройство для тестов без железа (`server/test/mock-device.js`)

### Фаза 3: Mobile App — прямой канал
- [ ] Добавить `DirectDeviceClient` (HTTP + WebSocket к ESP32)
- [ ] `ConnectionManager` с автоопределением LAN/WAN
- [ ] Переключить DashboardProvider на прямой канал
- [ ] Переключить ChartsProvider на прямую загрузку истории

### Фаза 4: Relay Server (опционально)
- [ ] WebSocket-прокси для WAN
- [ ] Клиент подключается к Relay
- [ ] ESP32 подключается к Relay
- [ ] Автовыбор: LAN → прямой, WAN → relay

### Фаза 5: Веб-сайт
- [ ] Разработка SPA (Vue.js / Svelte)
- [ ] Подключение по той же схеме (Signaling → прямой канал)

---

## Технические решения

| Решение | Обоснование |
|---------|-------------|
| ESPAsyncWebServer | Асинхронный, не блокирует loop(), поддерживает несколько клиентов |
| WebSocket на порту 81 | HTTP на 80, WS на 81 — стандартная практика, не конфликтуют |
| SD как основное хранилище | Уже реализовано, дешёво, надёжно для логов |
| In-memory signaling | Минимум зависимостей, не хранит чувствительные данные |
| MQTT как опция | Для совместимости с существующими инсталляциями |
| JSON-формат | Универсальный, уже используется |

## Безопасность

- **Signaling Server:** без авторизации (только регистрация устройств)
- **ESP32:** простой bearer-токен в заголовке для команд (опционально)
- **Локальная сеть:** предполагается доверенной (IoT в домашней/LAN сети)
- **WAN (Relay):** TLS + токен авторизации
