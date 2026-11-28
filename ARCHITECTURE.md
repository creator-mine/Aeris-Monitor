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

Реестр лежит в общей библиотеке `firmware/shared/sensor_modules` и используется
обоими проектами (контроллер и сенсорный модуль). На каждый обнаруженный адрес
создаётся **собственный клон драйвера**, поэтому два одинаковых датчика на
разных адресах не делят состояние драйвера.

```cpp
struct ActiveModule {
    SensorModule* driver;   // клон, принадлежит реестру
    uint8_t address;
    uint8_t muxAddress;     // 0 = прямая шина, 0x70..0x77 = за TCA9548A
    uint8_t muxChannel;
    unsigned long lastSeen; // последний успешный ответ на шине
    unsigned long nextReadAt;
    bool online;            // false = offline, модуль НЕ удаляется
    std::vector<Metric> cached;
};

class SensorRegistry {
    void registerDriver(SensorModule*);       // прототип драйвера
    void setMuxAddresses(const uint8_t*, size_t);
    void scanI2CBus(int sda, int scl);         // прямая шина + каналы мультиплексора
    void checkLiveness();                     // каждые 10 с, online/offline + re-init
    void poll();                              // чтение по readInterval() каждого модуля
    void forceRead();                         // чтение по требованию (команда read_sensor)
    unsigned long compositionRevision();      // растёт при смене состава модулей
    String modulesToJson();                   // status, address, mux, metrics
    String sensorsToJson();                   // только кэш, шину не трогает
};
```

**Саморегистрация драйвера** — фабрика сохраняется в `.cpp` драйвера, экземпляр
создаётся на первом сканировании, а не во время статической инициализации:

```cpp
// shared/sensor_modules/src/bme680_module.cpp
REGISTER_SENSOR(BME680Module)   // в конце файла драйвера
```

Добавление датчика = 2 файла в `shared/sensor_modules` + строка в `lib_deps` и
`library.json`. Ни `setup()`, ни приложение, ни панель, ни сервер не меняются.

**Идентификация датчиков.** `detect()` обязан проверять chip ID, а не только
ACK, если адрес делится с другим драйвером: BME680 (0x60) и BMP280 (0x58) сидят
на одних 0x76/0x77. Иначе первый зарегистрированный драйвер заберёт адрес у
второго. У SCD30 и INA219 chip ID нет, используется ACK (адреса 0x61 и 0x40).

**Мультиплексор TCA9548A.** Каналы включаются по одному байту перед
сканированием и перед каждым чтением; адреса мультиплексоров задаются в
`config.h`:

```c
#define I2C_MUX_ADDRESSES { 0x70, 0x00 }   // 0 = конец списка, {0x00} = без мультиплексора
```

Адреса 0x70–0x77 зарезервированы под мультиплексоры и всегда пропускаются при
сканировании. A0–A2 можно не разводить на пины: восемь адресов дают до 8
мультиплексоров, то есть до 64 датчиков на тех же двух проводах.

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
AA 55 01 01 00 43   -- заголовок: модуль #1, команда REGISTER, длина 67
01                  -- type_id = 0x01 (BME680)
06 42 4D 45 36 38 30 -- name = "BME680" (6 байт)
05                  -- 5 метрик
0B 74 65 6D 70 65 72 61 74 75 72 65 01 43         -- temperature, C
08 68 75 6D 69 64 69 74 79          01 25         -- humidity, %
08 70 72 65 73 73 75 72 65          03 68 50 61   -- pressure, hPa
03 69 61 71                        00            -- iaq, без единиц
0C 69 61 71 5F 61 63 63 75 72 61 63 79 00         -- iaq_accuracy, без единиц
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
            { "key": "temperature", "name": "Температура", "unit": "C" },
            { "key": "humidity",    "name": "Влажность",   "unit": "%" },
            { "key": "pressure",    "name": "Давление",    "unit": "hPa" },
            { "key": "iaq",         "name": "Качество воздуха (IAQ)", "unit": "" },
            { "key": "iaq_accuracy","name": "Точность IAQ", "unit": "" }
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
            "iaq": 42.0,
            "iaq_accuracy": 2.0
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

### 2.8 Добавление нового сенсорного модуля

**Таблица `type_id`** (выдаётся один раз, не переиспользуется):

| type_id | Драйвер | Адреса | Метрики | readInterval |
|---|---|---|---|---|
| 0x01 | BME680 | 0x76, 0x77 | `temperature`, `humidity`, `pressure`, `iaq`, `iaq_accuracy` | 3000 мс |
| 0x02 | BH1750 | 0x23, 0x5C | `illuminance` | 5000 мс |
| 0x03 | SCD30 | 0x61 | `scd30_co2`, `scd30_temperature`, `scd30_humidity` | 2000 мс |
| 0x04 | INA219 | 0x40 | `ina219_voltage`, `ina219_current`, `ina219_power` | 5000 мс |
| 0x05 | BMP280 | 0x76, 0x77 | `bmp280_temperature`, `bmp280_pressure` | 5000 мс |

**Правило именования метрик:** ключ = `<type>_<метрика>` в нижнем регистре
(`scd30_co2`, `bmp280_pressure`). Ключ становится темой MQTT
`iot/<device>/sensors/<key>` и колонкой CSV на SD, поэтому два модуля не должны
выдавать одинаковый ключ. Уже существующие ключи BME680 и BH1750 остаются
без префикса — переименование сломало бы историю в БД и приложении.

**Правило длины ключа:** ≤ 23 символов, единица измерения ≤ 7 символов
(ограничения приёмника UART-протокола).

**Порядок добавления датчика:**

1. `shared/sensor_modules/include/<name>_module.h` — класс, `typeId()`, `moduleName()`, `i2cAddresses()`, `metrics()`, `readInterval()`, `clone()`
2. `shared/sensor_modules/src/<name>_module.cpp` — `detect()`, `init()`, `read()`, `clone()` и `REGISTER_SENSOR(<Name>Module)` в конце файла
3. `shared/sensor_modules/library.json` — зависимость
4. `lib_deps` в **обоих** `platformio.ini` (контроллер и сенсорный модуль)

Пример минимального драйвера:

```cpp
bool SCD30Module::detect(uint8_t address) {   // нет chip ID -> только ACK
    Wire.beginTransmission(address);
    return Wire.endTransmission() == 0;
}

std::vector<Metric> SCD30Module::read() {
    std::vector<Metric> result;
    if (!_scdReady) return result;
    if (!_scd.dataReady()) return result;     // нет свежего замера
    if (!_scd.read()) return result;
    result.push_back({"scd30_co2", _scd.CO2, "ppm"});
    return result;
}
```

**Всё.** Система автоматически:
- Найдёт датчик на I2C при следующем сканировании (или за TCA9548A)
- Начнёт опрашивать с его `readInterval()` и публиковать данные
- Отобразит метрики в мобильном приложении и на веб-сайте
- Покажет `status: "offline"`, если датчик отвалится, не удаляя карточку
- Без единого изменения в других частях системы

### 2.9 Ограничения, которые нужно учитывать

| Ограничение | Значение | Где задано |
|---|---|---|
| Метрик на UART-модуль | 24 | `REMOTE_MODULE_MAX_METRICS` в `main_controller/src/main.cpp` |
| Модулей на контроллер | 8 | `REMOTE_MODULE_COUNT` |
| Регистрационный кадр | 512 байт | `REGISTER_PAYLOAD_MAX` в `sensor_module/src/main.cpp` |
| Кадр UART | < 1024 байт | `UART_BUFFER_SIZE` в `config.h` |
| Периодичность данных модуля | 5000 мс | `SENSOR_READ_INTERVAL_MS` |
| Каналов на TCA9548A | 8 | `SENSOR_MUX_CHANNEL_COUNT` |
| Частота опроса liveness | 10 с | `SENSOR_LIVENESS_INTERVAL_MS` |

Скорость публикации: MQTT и SD получают значение только при изменении больше
0.01 или раз в 60 секунд, иначе 13 метрик × 5 датчиков забивали бы SD-карту
за сутки.

**Инвариант позиционного протокола.** Контроллер сопоставляет значения с
ключами строго по порядку, поэтому все три источника обязаны совпадать:
`metrics()` драйвера, кэш `ActiveModule::cached` и `CMD_SENSOR_DATA`. Реестр
поэтому всегда держит в кэше ровно одну запись на каждую объявленную метрику
(в порядке `metrics()`), подставляя NAN, если значения пока нет — например,
SCD30 первые ~15 секунд после включения. Отправляющая сторона пишет float на
каждую объявленную метрику, поэтому появление шестого датчика не может сдвинуть
значения остальных на чужие ключи.

**Политика нечисловых значений.** NAN/INF не попадают ни в JSON (там был бы
невалидный `nan`), ни в MQTT, ни в CSV: `sensorsToJson()` пропускает метрику, а
контроллер при публикации и разборе UART-кадра проверяет `std::isfinite`.
Метрика без чтения просто отсутствует до первого корректного замера.

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

Главный контроллер (ESP32-C3 / ESP32-WROOM-32 / ESP32-C6 / ESP32-S3) становится сервером.

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
GET  /api/v1/sd/info            → { status, mounted, card_detected, type, total_bytes, used_bytes, free_bytes, used_pct }
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
- `ChartsProvider` — получает историю с SD через HTTP (`/sensors/history`) или,
  в режиме «Только MQTT» / при недоступном LAN, через MQTT-команду `history`
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
  ├── [LAN] ── HTTP GET /api/v1/sensors/history?since=<ts>&type=<type>
  │              └──► ESP32:80 (прямо) ──► SD-карта
  │
  └── [MQTT] ── iot/<id>/commands {command:"history", request_id, sensor, since, limit}
                 └──► ESP32 ──► SD-карта
                        └──► iot/<id>/sensors/history, чанки по 1,2 КБ
```

Чанки собираются приложением по `request_id`; последний помечен `last: true`.
Лимит одного запроса — 500 точек.

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

- **Signaling Server:** HTTP Basic с логинами MQTT (`device`/`app`)
- **ESP32:** тот же MQTT-логин для регистрации; команды идут через MQTT с ACL
- **Локальная сеть:** предполагается доверенной (IoT в домашней/LAN сети)
- **WAN (Relay):** TLS + Basic-авторизация
