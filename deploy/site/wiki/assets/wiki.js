/* Aeris Monitor — Wiki runtime
 * Shared across all /wiki/ pages.
 * Responsibilities: theme, RU/EN switching, sidebar, on-page TOC,
 * client-side search, prev/next pager, copy-code buttons, progress bar.
 */
(function () {
  'use strict';

  /* ---------------- page registry ---------------- */
  var PAGES = [
    {
      file: 'index.html', ic: '🗺',
      ru: 'Обзор и оглавление', en: 'Overview & contents',
      ruDesc: 'С чего начать: назначение вики, структура разделов и быстрые ссылки.',
      enDesc: 'Start here: what this wiki covers, how it is structured and quick links.',
      kw: 'оглавление обзор start index toc навигация overview contents вики wiki',
      sec: [
        ['kak-chitat', "Как читать вики", "How to read this wiki"],
        ['razdely', "Разделы вики", "Wiki sections"],
        ['s-chego-nachat', "С чего начать", "Where to start"],
        ['ssylki', "Прямые ссылки", "Direct links"]
      ]
    },
    {
      file: 'about.html', ic: '🎯',
      ru: 'О проекте', en: 'About the project',
      ruDesc: 'Проблема, идея, новизна, актуальность и границы применимости.',
      enDesc: 'Problem, idea, novelty, relevance and scope of the system.',
      kw: 'проект цель идея актуальность новизна зачем problem goal idea novelty why scope about',
      sec: [
        ['zachem', "Зачем это нужно", "Why it exists"],
        ['ideya', "Идея решения", "The idea"],
        ['novizna', "Что нового", "What is new"],
        ['aktualnost', "Актуальность", "Relevance"],
        ['granicy', "Границы применимости", "Scope & limits"],
        ['status', "Статус проекта", "Project status"],
        ['dorozhnaya-karta', "Дорожная карта", "Roadmap"]
      ]
    },
    {
      file: 'architecture.html', ic: '🏗',
      ru: 'Архитектура системы', en: 'System architecture',
      ruDesc: 'Компоненты, потоки данных, локальный API и поиск в сети, реестр модулей, отказоустойчивость и масштабирование.',
      enDesc: 'Components, data flows, the local API and discovery, module registry, fault tolerance and scaling.',
      kw: 'архитектура компоненты поток данных диаграмма реестр registry масштаб architecture components dataflow diagram scaling lan локальный discovery',
      sec: [
        ['obzor', "Обзор системы", "System overview"],
        ['potoki', "Потоки данных", "Data flows"],
        ['reestr-moduley', "Реестр модулей", "Module registry"],
        ['zhiznennyy-cikl', "Жизненный цикл модуля", "Module lifecycle"],
        ['otkazy', "Отказоустойчивость", "Fault tolerance"],
        ['masshtab', "Масштабирование", "Scaling"],
        ['model-dannyh', "Модель данных", "Data model"]
      ]
    },
    {
      file: 'data.html', ic: '📊',
      ru: 'Архитектура данных', en: 'Data architecture',
      ruDesc: 'MQTT-топики, JSONL-хранилище с роллапами, живой поток SSE, история и движок правил.',
      enDesc: 'MQTT topics, JSONL storage with rollups, the live SSE stream, history and the rules engine.',
      kw: 'данные data jsonl rollup роллап mqtt топик payload sse поток stream история history latest кэш правила rules engine ingest',
      sec: [
        ['obzor', "Поток данных сверху вниз", "The data flow, top to bottom"],
        ['mqtt', "Топики и форматы MQTT", "MQTT topics & formats"],
        ['hranilishche', "Хранилище: JSONL и роллапы", "Storage: JSONL & rollups"],
        ['sse', "Живой поток: SSE", "Live stream: SSE"],
        ['istoriya', "История: /api/v1/sensors", "History: /api/v1/sensors"],
        ['rules', "Движок правил", "Rules engine"],
        ['nastroyka', "Настройка", "Configuration"]
      ]
    },
    {
      file: 'hardware.html', ic: '🔌',
      ru: 'Железо и схемы', en: 'Hardware & schematics',
      ruDesc: 'Пины, питание, схемы UART/I²C, TCA9548A, BOM и типовые ошибки подключения.',
      enDesc: 'Pins, power, UART/I²C wiring, TCA9548A, BOM and common wiring mistakes.',
      kw: 'железо схемы пины pin wiring питание uart i2c tca9548a bom распайка платы hardware schematics pins power bom',
      sec: [
        ['komplekt', "Комплект оборудования", "Hardware kit"],
        ['piny', "Сводная таблица пинов", "Pin reference"],
        ['pitaniya', "Питание", "Power"],
        ['uart', "Схема UART-связи", "UART link schematic"],
        ['i2c', "Схема шины I²C", "I²C bus schematic"],
        ['mux', "Расширение I²C: TCA9548A", "Expanding I²C with TCA9548A"],
        ['bom', "Bill of materials", "Bill of materials"],
        ['oshibki-montazha', "Частые ошибки подключения", "Common wiring mistakes"]
      ]
    },
    {
      file: 'wiring.html', ic: '🧩',
      ru: 'Подключение датчиков', en: 'Sensor wiring',
      ruDesc: 'Распиновка BME680, BMP280, BH1750, SCD30 и INA219, выбор адреса I²C и свободные GPIO плат C3/C6/S3.',
      enDesc: 'Pin-by-pin wiring for BME680, BMP280, BH1750, SCD30 and INA219, I²C address selection and free GPIOs on C3/C6/S3.',
      kw: 'подключение распиновка пины gpio проводка bme680 bmp280 bh1750 scd30 ina219 адрес i2c sda scl питание 3.3v свободные пины unused wiring pinout',
      sec: [
        ['obshchaya-skhema', "Общая схема: четыре провода", "The common wiring: four wires"],
        ['tablica', "Сводная таблица", "Summary table"],
        ['datchiki', "Каждый датчик по отдельности", "Every sensor in detail"],
        ['bme680', "BME680", "BME680"],
        ['bmp280', "BMP280", "BMP280"],
        ['bh1750', "BH1750", "BH1750"],
        ['scd30', "SCD30", "SCD30"],
        ['ina219', "INA219", "INA219"],
        ['mux', "Если адреса совпадают: TCA9548A", "When addresses clash: TCA9548A"],
        ['platy', "Пины плат: что занято", "Board pins: what is used"],
        ['plata-c3', "ESP32-C3", "ESP32-C3"],
        ['plata-c6', "ESP32-C6", "ESP32-C6"],
        ['plata-s3', "ESP32-S3", "ESP32-S3"],
        ['plata-modul', "Сенсорный модуль C6", "C6 sensor module"],
        ['svobodnye-piny', "Сводка свободных пинов", "Free-pin summary"],
        ['proverka', "Проверка подключения", "Checking the wiring"]
      ]
    },
    {
      file: 'sensors.html', ic: '🌡',
      ru: 'Датчики и драйверы', en: 'Sensors & drivers',
      ruDesc: 'Реестр драйверов, type_id, чип-детекция, метрики, отказоустойчивость и добавление своего датчика.',
      enDesc: 'Driver registry, type_id, chip detection, metrics, resilience and adding your own sensor.',
      kw: 'датчики драйверы реестр type_id чип bme680 bmp280 sht scd30 ina219 bh1750 aht25 dht sensors drivers registry питание вольт напряжение 3.3v 5v supply voltage power',
      sec: [
        ['reestr', "Реестр драйверов", "Driver registry"],
        ['tipy-dannyh', "Типы и коды датчиков", "Sensor types & codes"],
        ['detekciya', "Определение по chip ID", "Detection by chip ID"],
        ['metriki', "Метрики и единицы", "Metrics & units"],
        ['otkazoustoychivost', "Отказоустойчивость драйверов", "Driver resilience"],
        ['tca-datchiki', "Датчики за TCA9548A", "Sensors behind TCA9548A"],
        ['svoy-datchik', "Как добавить свой датчик", "Adding your own sensor"]
      ]
    },
    {
      file: 'firmware.html', ic: '⚙',
      ru: 'Прошивка и протокол', en: 'Firmware & protocol',
      ruDesc: 'Сборка PlatformIO, менеджер Wi-Fi, OTA с откатом, поиск в локальной сети, структура кода и бинарный UART-протокол с CRC-16.',
      enDesc: 'PlatformIO build, Wi-Fi manager, OTA with rollback, LAN discovery, code layout and the binary UART protocol with CRC-16.',
      kw: 'прошивка сборка platformio pio прошить flash ota обновление uart протокол crc кадр frame firmware build flash lan udp discovery 8266 поиск сети wifi wi-fi профили сети auto manual сканирование',
      sec: [
        ['sostav', "Состав репозитория", "Repository layout"],
        ['sborka', "Сборка прошивок", "Building the firmware"],
        ['pervyy-zapusk', "Первичная прошивка и настройка", "Initial flash & setup"],
        ['wifi', "Менеджер Wi-Fi", "Wi-Fi manager"],
        ['ota', "Обновление по воздуху", "Over-the-air updates"],
        ['lan', "Поиск в локальной сети", "LAN discovery"],
        ['struktura', "Структура кода контроллера", "Controller code layout"],
        ['protocol', "UART-протокол", "UART protocol"],
        ['crc', "CRC-16 и целостность кадра", "CRC-16 & frame integrity"],
        ['potok-registracii', "Поток регистрации", "Registration flow"]
      ]
    },
    {
      file: 'app.html', ic: '📱',
      ru: 'Мобильное приложение', en: 'Mobile application',
      ruDesc: 'Flutter-приложение: режимы подключения, Wi-Fi-менеджер, обновления, автопоиск устройств в LAN, экраны, графики, аварии, smart rules, прошивка из .bin или ссылки.',
      enDesc: 'Flutter app: connection modes, Wi-Fi manager, updates, automatic LAN discovery, screens, charts, alerts, smart rules, firmware from a .bin or link.',
      kw: 'приложение flutter android ios экраны графики аварии правила smart rules прошивки otа приложение app mobile dashboard lan udp discovery автопоиск wifi wi-fi авто ручной обновления updates github releases secure storage',
      sec: [
        ['vozmozhnosti', "Возможности", "Features"],
        ['rezhimy', "Режимы подключения", "Connection modes"],
        ['wifi', "Wi-Fi: до восьми сетей", "Wi-Fi: up to eight networks"],
        ['ekrany', "Экраны", "Screens"],
        ['grafiki', "Графики и статистика", "Charts & statistics"],
        ['avarii', "Аварии и пороги", "Alerts & thresholds"],
        ['pravila', "Smart rules", "Smart rules"],
        ['sborka-proshivok', "Сборка прошивок из приложения", "Building firmware from the app"],
        ['nastroyki', "Настройки и учётные данные", "Settings & credentials"]
      ]
    },
    {
      file: 'server.html', ic: '🖥',
      ru: 'Сервер и развёртывание', en: 'Server & deployment',
      ruDesc: 'Сигнальный сервер, Mosquitto, nginx, TLS, удалённое переключение Wi-Fi, веб-панель, переменные окружения и бэкапы.',
      enDesc: 'Signaling server, Mosquitto, nginx, TLS, remote Wi-Fi switching, web panel, environment variables and backups.',
      kw: 'сервер развёртывание deployment nginx mosquitto mqtt tls сертификат systemd бэкап backup переменные окружения vps docker panel панель wifi wi-fi удалённое переключение prepare commit',
      sec: [
        ['sostav', "Что стоит на сервере", "What runs on the server"],
        ['signalnyy', "Сигнальный сервер", "Signaling server"],
        ['remote-wifi', "Удалённое переключение Wi-Fi", "Remote Wi-Fi switching"],
        ['mqtt', "Брокер Mosquitto", "Mosquitto broker"],
        ['nginx', "nginx и маршрутизация", "nginx & routing"],
        ['razvertyvanie', "Развёртывание с нуля", "Deploying from scratch"],
        ['peremennye', "Переменные окружения", "Environment variables"],
        ['rezervnoe', "Резервное копирование", "Backup & restore"],
        ['bezopasnost', "Безопасность", "Security"]
      ]
    },
    {
      file: 'api.html', ic: '📡',
      ru: 'Справочник API', en: 'API reference',
      ruDesc: 'REST и WebSocket контроллера, Wi-Fi, поиск в локальной сети, MQTT-топики, CSV на SD, справочник ошибок.',
      enDesc: 'Controller REST and WebSocket, Wi-Fi, LAN discovery, MQTT topics, SD CSV format, error reference.',
      kw: 'api rest websocket mqtt топики topics csv json ошибки error коды http endpoint документация reference lan udp discovery 8266 wifi wi-fi профили prepare commit',
      sec: [
        ['obzor', "Два разных интерфейса", "Two different interfaces"],
        ['ustroystvo', "API устройства", "Device API"],
        ['wifi-http', "Wi-Fi", "Wi-Fi"],
        ['komandy', "Команды устройству", "Device commands"],
        ['websocket', "WebSocket устройства", "Device WebSocket"],
        ['server-api', "API сигнального сервера", "Signaling server API"],
        ['kod', "Коды ответа и ошибки", "Status codes and errors"],
        ['mqtt', "Топики MQTT", "MQTT topics"],
        ['csv', "Формат CSV на карте", "CSV format on the card"],
        ['ota', "Манифест прошивки", "Firmware manifest"],
        ['primer', "Готовые примеры", "Worked examples"]
      ]
    },
    {
      file: 'faq.html', ic: '🛟',
      ru: 'FAQ и траблешут', en: 'FAQ & troubleshooting',
      ruDesc: 'Разбор типовых проблем: датчик не найден, нет данных, рассинхрон метрик, потеря SD, откат прошивки.',
      enDesc: 'Common problems: sensor not found, no data, metric desync, lost SD card, firmware rollback.',
      kw: 'faq проблемы ошибки не работает отладка troubleshoot debug не найден нет данных сбой reset help faq problems',
      sec: [
        ['obshchie', "Общие вопросы", "General"],
        ['podklyuchenie', "Подключение и настройка", "Wiring & setup"],
        ['dannye', "Данные и история", "Data & history"],
        ['obnovleniya', "Прошивки и обновления", "Firmware & updates"],
        ['razrabotka', "Развёртывание и разработка", "Deployment & development"]
      ]
    }
  ];

  var UI = {
    search: { ru: 'Поиск по вики…', en: 'Search the wiki…' },
    searchEmpty: { ru: 'Ничего не найдено', en: 'Nothing found' },
    searchHint: { ru: 'по страницам и разделам', en: 'across pages and sections' },
    onThisPage: { ru: 'На этой странице', en: 'On this page' },
    home: { ru: 'Главная сайта', en: 'Site home' },
    wiki: { ru: 'Вики', en: 'Wiki' },
    sections: { ru: 'Разделы', en: 'Sections' },
    prev: { ru: '← Предыдущая', en: '← Previous' },
    next: { ru: 'Следующая →', en: 'Next →' },
    copy: { ru: 'Копировать', en: 'Copy' },
    copied: { ru: 'Скопировано', en: 'Copied' },
    edit: {
      ru: 'Нашли неточность? Исходники вики лежат в репозитории проекта — правки приветствуются.',
      en: 'Found an inaccuracy? The wiki sources live in the project repository — contributions welcome.'
    },
    fw: { ru: 'версия прошивки', en: 'firmware version' },
    appVer: { ru: 'версия приложения', en: 'app version' },
    serverVer: { ru: 'версия сервера', en: 'server version' },
    updated: { ru: 'обновлено', en: 'updated' },
    menu: { ru: 'Меню', en: 'Menu' }
  };

  var META = {
    fw: '1.3.9',
    app: '1.3.8',
    server: '0.4.2',
    updated: '2026-11-21'
  };

  var LANGS = ['ru', 'en'];
  var ls = {
    get: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set: function (k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } }
  };

  var state = {
    lang: LANGS.indexOf(ls.get('lang')) > -1 ? ls.get('lang') : 'ru',
    theme: ls.get('theme') === 'light' ? 'light' : 'dark',
    current: document.body.getAttribute('data-page') || ''
  };

  function t(key) {
    var entry = UI[key];
    if (!entry) return key;
    return entry[state.lang] || entry.ru;
  }

  /* ---------------- theme ---------------- */
  function applyTheme() {
    if (state.theme === 'light') {
      document.documentElement.setAttribute('data-theme', 'light');
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
    var btn = document.getElementById('themeBtn');
    if (btn) btn.textContent = state.theme === 'light' ? '☀️' : '🌙';
  }

  function toggleTheme() {
    state.theme = state.theme === 'light' ? 'dark' : 'light';
    ls.set('theme', state.theme);
    applyTheme();
  }

  /* ---------------- language ---------------- */
  function applyLang() {
    document.documentElement.lang = state.lang;

    var nodes = document.querySelectorAll('[data-ru][data-en]');
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].textContent = nodes[i].getAttribute('data-' + state.lang) || '';
    }

    var rich = document.querySelectorAll('[data-ru-html][data-en-html]');
    for (var j = 0; j < rich.length; j++) {
      rich[j].innerHTML = rich[j].getAttribute('data-' + state.lang + '-html') || '';
    }

    var attrNodes = document.querySelectorAll('[data-ru-attr][data-en-attr]');
    for (var k = 0; k < attrNodes.length; k++) {
      var el = attrNodes[k];
      var ruList = el.getAttribute('data-ru-attr').split(',');
      var enList = el.getAttribute('data-en-attr').split(',');
      var list = state.lang === 'ru' ? ruList : enList;
      for (var a = 0; a < list.length; a++) {
        var name = list[a].trim();
        if (!name) continue;
        el.setAttribute(name, el.getAttribute('data-' + state.lang) || '');
      }
    }

    var lb = document.getElementById('langBtn');
    if (lb) lb.textContent = state.lang === 'ru' ? 'EN' : 'RU';

    document.title = document.title.replace(/\s·\s.*$/, '') +
      ' · ' + (state.lang === 'ru' ? 'Вики' : 'Wiki');

    renderSidebar();
    renderToc();
    renderPager();
    buildSearchIndex();
    var q = document.getElementById('searchInput');
    if (q && q.value.trim()) runSearch(q.value.trim());
    markActiveHeading();
  }

  function toggleLang() {
    var i = LANGS.indexOf(state.lang);
    state.lang = LANGS[(i + 1) % LANGS.length];
    ls.set('lang', state.lang);
    applyLang();
  }

  function getText(el) {
    var v = el.getAttribute('data-' + state.lang);
    if (v === null || v === undefined || v === '') v = el.getAttribute('data-ru');
    return v || (el.textContent || '').trim();
  }

  function pageTitle(p) { return p[state.lang] || p.ru; }

  /* ---------------- sidebar ---------------- */
  function renderSidebar() {
    var nav = document.getElementById('sidebar');
    if (!nav) return;

    var html = '';
    html += '<a class="side-link home" href="../index.html"><span class="sl-ic">🏠</span>' +
      '<span>' + esc(t('home')) + '</span></a>';
    html += '<div class="side-label">' + esc(t('sections')) + '</div>';
    for (var i = 0; i < PAGES.length; i++) {
      var p = PAGES[i];
      var cls = 'side-link' + (p.file === state.current ? ' active' : '');
      html += '<a class="' + cls + '" href="' + p.file + '" data-file="' + p.file + '">' +
        '<span class="sl-ic">' + p.ic + '</span><span>' + esc(pageTitle(p)) + '</span></a>';
    }
    nav.innerHTML = html;
  }

  /* ---------------- on-page TOC ---------------- */
  function renderToc() {
    var box = document.getElementById('toc');
    if (!box) return;

    var heads = document.querySelectorAll('.prose > h2[id], .prose > h3[id]');
    var html = '<div class="toc-label">' + esc(t('onThisPage')) + '</div>';
    if (!heads.length) {
      html += '<div style="color:var(--muted);font-size:12.5px;padding-left:12px">—</div>';
    }
    for (var i = 0; i < heads.length; i++) {
      var h = heads[i];
      var lvl = h.tagName === 'H3' ? ' lvl-3' : '';
      html += '<a class="toc-entry' + lvl + '" href="#' + h.id + '" data-target="' + h.id + '">' +
        esc(getText(h)) + '</a>';
    }

    html += '<div class="meta">';
    html += metaRow('fw', t('fw') + ': ' + META.fw);
    html += metaRow('app', t('appVer') + ': ' + META.app);
    html += metaRow('srv', t('serverVer') + ': ' + META.server);
    html += metaRow('upd', t('updated') + ': ' + META.updated);
    html += '</div>';
    box.innerHTML = html;
  }

  function metaRow(_id, text) {
    return '<div class="row"><span class="k"></span>' +
      '<span class="v">' + esc(text) + '</span></div>';
  }

  function markActiveHeading() {
    var links = document.querySelectorAll('#toc .toc-entry');
    if (!links.length) return;
    var pos = window.scrollY + 140;
    var currentId = links[0].getAttribute('data-target');
    for (var i = 0; i < links.length; i++) {
      var el = document.getElementById(links[i].getAttribute('data-target'));
      if (el && el.offsetTop <= pos) currentId = links[i].getAttribute('data-target');
    }
    for (var j = 0; j < links.length; j++) {
      links[j].classList.toggle('active', links[j].getAttribute('data-target') === currentId);
    }
  }

  /* ---------------- pager ---------------- */
  function renderPager() {
    var box = document.getElementById('pager');
    if (!box) return;

    var idx = -1;
    for (var i = 0; i < PAGES.length; i++) if (PAGES[i].file === state.current) idx = i;

    var prev = idx > 0 ? PAGES[idx - 1] : null;
    var next = idx > -1 && idx < PAGES.length - 1 ? PAGES[idx + 1] : null;

    var html = prev
      ? '<a class="prev" href="' + prev.file + '"><div class="dir">' + esc(t('prev')) + '</div>' +
        '<div class="t">' + prev.ic + ' ' + esc(pageTitle(prev)) + '</div></a>'
      : '<span class="empty"></span>';

    html += next
      ? '<a class="next" href="' + next.file + '"><div class="dir">' + esc(t('next')) + '</div>' +
        '<div class="t">' + next.ic + ' ' + esc(pageTitle(next)) + '</div></a>'
      : '<span class="empty"></span>';

    box.innerHTML = html;
  }

  /* ---------------- search ---------------- */
  var INDEX = [];

  function buildSearchIndex() {
    INDEX = [];
    for (var i = 0; i < PAGES.length; i++) {
      var p = PAGES[i];
      INDEX.push({
        title: pageTitle(p),
        file: p.file,
        hash: '',
        desc: state.lang === 'ru' ? p.ruDesc : p.enDesc,
        kw: (p.kw + ' ' + p.ru + ' ' + p.en + ' ' + p.ruDesc + ' ' + p.enDesc).toLowerCase()
      });
      for (var s = 0; s < p.sec.length; s++) {
        INDEX.push({
          title: pageTitle(p),
          secTitle: state.lang === 'ru' ? p.sec[s][1] : p.sec[s][2],
          file: p.file,
          hash: p.sec[s][0],
          desc: state.lang === 'ru' ? p.ruDesc : p.enDesc,
          kw: (p.kw + ' ' + p.sec[s][1] + ' ' + p.sec[s][2] + ' ' + p.ru + ' ' + p.en).toLowerCase()
        });
      }
    }
  }

  function norm(s) { return (s || '').toLowerCase(); }

  function runSearch(q) {
    var box = document.getElementById('searchResults');
    if (!box) return;
    var nq = norm(q);
    var hits = [];

    for (var i = 0; i < INDEX.length && hits.length < 40; i++) {
      var it = INDEX[i];
      var inTitle = norm(it.title).indexOf(nq) > -1;
      var inSec = it.secTitle ? norm(it.secTitle).indexOf(nq) > -1 : false;
      var inKw = it.kw.indexOf(nq) > -1;
      if (inTitle || inSec || inKw) {
        hits.push({ it: it, score: (inSec ? 3 : 0) + (inTitle ? 2 : 0) + (inKw ? 1 : 0) });
      }
    }

    hits.sort(function (a, b) { return b.score - a.score; });

    if (!hits.length) {
      box.innerHTML = '<div class="empty">' + esc(t('searchEmpty')) + '</div>';
      box.classList.add('open');
      return;
    }

    var seen = {};
    var html = '';
    for (var h = 0; h < hits.length && html !== ''; h++) {
      var row = hits[h].it;
      var key = row.file + '#' + row.hash;
      if (seen[key]) continue;
      seen[key] = true;
      var href = row.file + (row.hash ? '#' + row.hash : '');
      html += '<a href="' + href + '">' +
        '<div class="r-title">' + esc(row.title) +
        (row.secTitle ? ' <span class="r-sec">› ' + esc(row.secTitle) + '</span>' : '') + '</div>' +
        '<div class="r-desc">' + esc(row.desc) + '</div></a>';
      if (Object.keys(seen).length >= 14) break;
    }
    box.innerHTML = html;
    box.classList.add('open');
  }

  function closeSearch() {
    var box = document.getElementById('searchResults');
    if (box) box.classList.remove('open');
  }

  /* ---------------- mobile sidebar ---------------- */
  function toggleSidebar(force) {
    var sb = document.getElementById('sidebar');
    var sc = document.getElementById('scrim');
    if (!sb || !sc) return;
    var open = typeof force === 'boolean' ? force : !sb.classList.contains('open');
    sb.classList.toggle('open', open);
    sc.classList.toggle('open', open);
  }

  /* ---------------- copy buttons ---------------- */
  function addCopyButtons() {
    var blocks = document.querySelectorAll('.prose pre');
    for (var i = 0; i < blocks.length; i++) {
      (function (block) {
        var btn = document.createElement('button');
        btn.className = 'copy-btn';
        btn.type = 'button';
        btn.textContent = t('copy');
        btn.addEventListener('click', function () {
          var text = block.innerText;
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function () {
              btn.textContent = t('copied');
              setTimeout(function () { btn.textContent = t('copy'); }, 1400);
            });
          }
        });
        block.appendChild(btn);
      })(blocks[i]);
    }
  }

  /* ---------------- progress ---------------- */
  function updateProgress() {
    var bar = document.getElementById('progress');
    if (!bar) return;
    var h = document.documentElement.scrollHeight - window.innerHeight;
    var pct = h > 0 ? (window.scrollY / h) * 100 : 0;
    bar.style.width = Math.min(100, Math.max(0, pct)) + '%';
  }

  /* ---------------- helpers ---------------- */
  function esc(s) {
    return String(s === null || s === undefined ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  /* ---------------- init ---------------- */
  function init() {
    applyTheme();
    buildSearchIndex();
    renderSidebar();
    renderToc();
    renderPager();
    applyLang();
    addCopyButtons();

    var themeBtn = document.getElementById('themeBtn');
    if (themeBtn) themeBtn.addEventListener('click', toggleTheme);

    var langBtn = document.getElementById('langBtn');
    if (langBtn) langBtn.addEventListener('click', toggleLang);

    var sideBtn = document.getElementById('sideToggle');
    if (sideBtn) sideBtn.addEventListener('click', function () { toggleSidebar(); });

    var scrim = document.getElementById('scrim');
    if (scrim) scrim.addEventListener('click', function () { toggleSidebar(false); });

    document.addEventListener('click', function (e) {
      var sb = document.getElementById('sidebar');
      if (sb && sb.classList.contains('open') && window.innerWidth > 900) toggleSidebar(false);
    });

    var input = document.getElementById('searchInput');
    if (input) {
      input.setAttribute('placeholder', t('search'));
      input.addEventListener('input', function () {
        if (input.value.trim().length >= 2) runSearch(input.value.trim());
        else closeSearch();
      });
      input.addEventListener('focus', function () {
        if (input.value.trim().length >= 2) runSearch(input.value.trim());
      });
      input.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') { input.value = ''; closeSearch(); input.blur(); }
        if (e.key === 'Enter') {
          var first = document.querySelector('#searchResults a');
          if (first) { e.preventDefault(); window.location.href = first.getAttribute('href'); }
        }
      });
    }

    document.addEventListener('click', function (e) {
      if (!e.target.closest || !e.target.closest('.top-search')) closeSearch();
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === '/' && !/^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName)) {
        if (input) { e.preventDefault(); input.focus(); }
      }
    });

    window.addEventListener('scroll', updateProgress, { passive: true });
    window.addEventListener('scroll', markActiveHeading, { passive: true });
    updateProgress();
    markActiveHeading();

    if (window.location.hash) {
      var target = document.getElementById(window.location.hash.slice(1));
      if (target) setTimeout(function () { target.scrollIntoView(); }, 30);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
