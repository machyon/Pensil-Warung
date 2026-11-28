import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/api_exception.dart';

http.Response _json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', 'x-request-id': 'req-1'},
    );

void main() {
  test('sends bearer and builds the URL from the base', () async {
    late http.BaseRequest seen;
    final api = ApiClient(
      baseUrl: 'http://x',
      token: () => 'tok',
      client: MockClient((r) async {
        seen = r;
        return _json(200, {'status': 'ok'});
      }),
    );
    expect(await api.get('/health'), {'status': 'ok'});
    expect(seen.url.toString(), 'http://x/health');
    expect(seen.headers['Authorization'], 'Bearer tok');
  });

  test('envelope becomes ApiException', () async {
    final api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((_) async => _json(422, {
            'error': {'code': 'invalid_value', 'message': 'Salah.', 'details': {'field': 'price'}}
          })),
    );
    await expectLater(
      api.post('/api/v1/products', body: {'a': 1}),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 422)
          .having((e) => e.code, 'code', 'invalid_value')
          .having((e) => e.message, 'message', 'Salah.')
          .having((e) => e.details?['field'], 'field', 'price')
          .having((e) => e.requestId, 'requestId', 'req-1')),
    );
  });

  test('401 unauthorized on an authed call signs out; login failure does not', () async {
    var signedOut = 0;
    final unauthorized = MockClient((_) async =>
        _json(401, {'error': {'code': 'unauthorized', 'message': 'Masuk lagi.'}}));
    final authed = ApiClient(
        baseUrl: 'http://x', client: unauthorized, token: () => 'tok', onUnauthorized: () => signedOut++);
    await expectLater(authed.get('/api/v1/me'), throwsA(isA<ApiException>()));
    expect(signedOut, 1);

    final login = ApiClient(
      baseUrl: 'http://x',
      onUnauthorized: () => signedOut++,
      client: MockClient((_) async =>
          _json(401, {'error': {'code': 'invalid_credentials', 'message': 'Salah.'}})),
    );
    await expectLater(login.post('/api/v1/auth/login', body: {}), throwsA(isA<ApiException>()));
    expect(signedOut, 1);
  });

  test('socket error and timeout become NetworkException', () async {
    final down = ApiClient(
        baseUrl: 'http://x', client: MockClient((_) async => throw http.ClientException('refused')));
    await expectLater(down.get('/health'), throwsA(isA<NetworkException>()));

    final slow = ApiClient(
      baseUrl: 'http://x',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) => Future.delayed(const Duration(seconds: 1), () => _json(200, {}))),
    );
    await expectLater(slow.get('/health'), throwsA(isA<NetworkException>()));
  });
}
