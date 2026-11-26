import 'package:aeris/core/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ApiClient build({bool? enableLogging}) => ApiClient(
        baseUrl: 'http://127.0.0.1:8080',
        username: 'aeris',
        password: 'secret',
        enableLogging: enableLogging,
      );

  test('release builds install no request logger', () {
    final client = build(enableLogging: false);

    expect(client.debugInterceptors.whereType<LogInterceptor>(), isEmpty);
  });

  test('debug logger never prints headers or bodies', () {
    final client = build(enableLogging: true);

    final logger = client.debugInterceptors.whereType<LogInterceptor>().single;
    expect(logger.requestHeader, isFalse);
    expect(logger.responseHeader, isFalse);
    expect(logger.requestBody, isFalse);
    expect(logger.responseBody, isFalse);
  });
}
