import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:aeris/core/api/firmware_fetcher.dart';

class _FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('aeris-firmware-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writeBin(String name, List<int> bytes) async {
    final file = File(p.join(temp.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  test('stages a valid local .bin and preserves metadata', () async {
    final source = await writeBin(
      'iot-modular-esp32c6-v1.3.2.bin',
      [0xE9, 0x01, 0x02, 0x03, 0x04],
    );
    final fetcher = FirmwareFetcher(storageDir: temp);

    final staged = await fetcher.stageLocalFile(
      source.path,
      preferredDeviceType: 'esp32-c3',
    );

    expect(staged.deviceType, 'esp32-c6');
    expect(staged.version, '1.3.2');
    expect(staged.fileName, 'iot-modular-esp32c6-v1.3.2.bin');
    expect(staged.sizeBytes, 5);
    expect(staged.sha256.length, 64);
    expect(await File(staged.path).exists(), isTrue);
  });

  test('treats a generic firmware.bin as the selected board image', () async {
    final source = await writeBin('firmware.bin', [0xE9, 0x10]);
    final fetcher = FirmwareFetcher(storageDir: temp);

    final staged = await fetcher.stageLocalFile(
      source.path,
      preferredDeviceType: 'esp32-c6',
    );

    expect(staged.deviceType, 'esp32-c6');
  });

  test('rejects an empty file', () async {
    final source = await writeBin('empty.bin', []);
    final fetcher = FirmwareFetcher(storageDir: temp);

    expect(
      () =>
          fetcher.stageLocalFile(source.path, preferredDeviceType: 'esp32-c6'),
      throwsA(isA<FirmwareFetchException>()),
    );
  });

  test('rejects a non-ESP image', () async {
    final source = await writeBin('fake.bin', [0x00, 0x01, 0x02]);
    final fetcher = FirmwareFetcher(storageDir: temp);

    expect(
      () =>
          fetcher.stageLocalFile(source.path, preferredDeviceType: 'esp32-c6'),
      throwsA(
        isA<FirmwareFetchException>().having(
          (e) => e.message,
          'message',
          contains('0xE9'),
        ),
      ),
    );
  });

  test('downloads a direct .bin and verifies the image', () async {
    final bytes = [0xE9, 0x11, 0x22, 0x33];
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (options) async => ResponseBody.fromBytes(
          bytes,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream'],
          },
        ),
      );
    final fetcher = FirmwareFetcher(dio: dio, storageDir: temp);

    final staged = await fetcher.downloadFromUrl(
      'https://example.com/main_esp32-c6.bin',
      preferredDeviceType: 'esp32-c6',
    );

    expect(staged.deviceType, 'esp32-c6');
    expect(staged.downloaded, isTrue);
    expect(staged.sizeBytes, bytes.length);
    expect(await File(staged.path).readAsBytes(), bytes);
  });

  test('prefers an explicit manifest version over the file name', () async {
    final bytes = [0xE9, 0x11, 0x22, 0x33];
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (options) async => ResponseBody.fromBytes(
          bytes,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream'],
          },
        ),
      );
    final fetcher = FirmwareFetcher(dio: dio, storageDir: temp);

    final staged = await fetcher.downloadFromUrl(
      'https://spe4naz.online/fw/main_esp32-c6.bin',
      preferredDeviceType: 'esp32-c6',
      version: '1.3.2',
    );

    expect(staged.version, '1.3.2');
  });

  test('rejects an HTML response instead of saving it as firmware', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (options) async => ResponseBody.fromString(
          '<html>not a firmware</html>',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/html'],
          },
        ),
      );
    final fetcher = FirmwareFetcher(dio: dio, storageDir: temp);

    expect(
      () => fetcher.downloadFromUrl(
        'https://example.com/main_esp32-c6.bin',
        preferredDeviceType: 'esp32-c6',
      ),
      throwsA(isA<FirmwareFetchException>()),
    );
  });

  test('checks SHA-256 against a manifest', () async {
    final bytes = [0xE9, 0x01, 0x02];
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (options) async => ResponseBody.fromBytes(bytes, 200),
      );
    final fetcher = FirmwareFetcher(dio: dio, storageDir: temp);

    expect(
      () => fetcher.downloadFromUrl(
        'https://example.com/main_esp32-c6.bin',
        preferredDeviceType: 'esp32-c6',
        expectedSha256: '0' * 64,
      ),
      throwsA(
        isA<FirmwareFetchException>().having(
          (e) => e.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );
  });

  test('selects the matching asset from a GitHub release', () async {
    final bytes = [0xE9, 0xAA, 0xBB];
    final release = jsonEncode({
      'tag_name': 'v1.3.2',
      'assets': [
        {
          'name': 'main_esp32-c3.bin',
          'browser_download_url': 'https://example.com/main_esp32-c3.bin',
          'size': bytes.length,
        },
        {
          'name': 'main_esp32-c6.bin',
          'browser_download_url': 'https://example.com/main_esp32-c6.bin',
          'size': bytes.length,
        },
      ],
    });
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter((options) async {
        if (options.uri.host == 'api.github.com') {
          return ResponseBody.fromString(
            release,
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }
        return ResponseBody.fromBytes(bytes, 200);
      });
    final fetcher = FirmwareFetcher(dio: dio, storageDir: temp);

    final staged = await fetcher.downloadFromUrl(
      'https://github.com/owner/repo/releases/latest',
      preferredDeviceType: 'esp32-c6',
    );

    expect(staged.deviceType, 'esp32-c6');
    expect(staged.version, '1.3.2');
    expect(staged.fileName, 'main_esp32-c6.bin');
  });
}
