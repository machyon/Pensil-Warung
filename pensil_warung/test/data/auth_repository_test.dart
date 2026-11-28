import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/api_exception.dart';
import 'package:pensil_warung/data/repositories/auth_repository.dart';

const _user = {
  'id': 'u1',
  'display_name': 'Siti',
  'username': 'siti',
  'email': 'siti@example.com',
  'role': 'user',
  'permissions': ['product.manage'],
  'has_password': false,
};

AuthRepository _repo(int status, Object body, [void Function(http.Request)? seen]) =>
    AuthRepository(ApiClient(
      baseUrl: 'http://x',
      client: MockClient((r) async {
        seen?.call(r);
        return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
      }),
    ));

void main() {
  test('200 existing user, sends id_token', () async {
    late http.Request req;
    final r = await _repo(200, {'token': 't', 'user': _user, 'created': false}, (x) => req = x).google('g');
    expect(req.url.path, '/api/v1/auth/google');
    expect(jsonDecode(req.body), {'id_token': 'g'});
    expect((r.token, r.user.email, r.created), ('t', 'siti@example.com', false));
  });

  test('201 new user', () async {
    final r = await _repo(201, {'token': 't', 'user': _user, 'created': true}).google('g');
    expect(r.created, true);
  });

  test('409 email_registered throws ApiException with the server message', () async {
    await expectLater(
      _repo(409, {'error': {'code': 'email_registered', 'message': 'Email ini sudah terdaftar.'}}).google('g'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'email_registered')
          .having((e) => e.message, 'message', 'Email ini sudah terdaftar.')),
    );
  });
}
