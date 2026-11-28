import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/repositories/auth_repository.dart';
import 'package:pensil_warung/data/session.dart';
import 'package:pensil_warung/ui/auth/login_screen.dart';
import 'package:pensil_warung/ui/core/widgets/buttons.dart';
import 'package:pensil_warung/ui/auth/register_screen.dart';
import 'package:provider/provider.dart';

const _user = {
  'id': 'u1',
  'display_name': 'Siti',
  'username': 'siti',
  'email': 'siti@example.com',
  'role': 'user',
  'permissions': <String>[],
  'has_password': true,
};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<Session> _pump(WidgetTester tester, Widget screen, http.Response Function(http.Request) reply) async {
  FlutterSecureStorage.setMockInitialValues({});
  final session = Session();
  final repo = AuthRepository(ApiClient(baseUrl: 'http://x', client: MockClient((r) async => reply(r))));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      Provider.value(value: repo),
    ],
    child: MaterialApp(home: screen),
  ));
  return session;
}

void main() {
  testWidgets('login: wrong password shows the red state and typing clears it', (tester) async {
    final session = await _pump(tester, const LoginScreen(),
        (_) => _json(401, {'error': {'code': 'invalid_credentials', 'message': 'Salah.'}}));
    await tester.enterText(find.byType(TextField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(1), 'salahsalah');
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.text('Email atau kata sandi salah'), findsOneWidget);
    expect(session.signedIn, isFalse);

    await tester.enterText(find.byType(TextField).at(1), 'x');
    await tester.pump();
    expect(find.text('Email atau kata sandi salah'), findsNothing);
  });

  testWidgets('login: success sets the session', (tester) async {
    late http.Request seen;
    final session = await _pump(tester, const LoginScreen(), (r) {
      seen = r;
      return _json(200, {'token': 't', 'user': _user});
    });
    await tester.enterText(find.byType(TextField).at(0), ' siti@example.com ');
    await tester.enterText(find.byType(TextField).at(1), 'rahasia123');
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(jsonDecode(seen.body), {'email': 'siti@example.com', 'password': 'rahasia123'});
    expect(session.token, 't');
    expect(session.signedIn, isTrue);
  });

  testWidgets('register: client checks block the request', (tester) async {
    var calls = 0;
    await _pump(tester, const RegisterScreen(), (_) {
      calls++;
      return _json(201, {'token': 't', 'user': _user});
    });
    await tester.enterText(find.byType(TextField).at(1), 'a@b.c');
    await tester.enterText(find.byType(TextField).at(2), 'pendek');
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    expect(find.text('Nama tidak boleh kosong.'), findsOneWidget);
    expect(find.text('Password harus 8 sampai 128 karakter.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('register: 409 email_taken shows under the email field; success sets the session', (tester) async {
    var taken = true;
    final session = await _pump(tester, const RegisterScreen(), (r) {
      if (taken) return _json(409, {'error': {'code': 'email_taken', 'message': 'Email sudah digunakan.'}});
      expect(jsonDecode(r.body)['display_name'], 'Siti');
      return _json(201, {'token': 't', 'user': _user});
    });
    await tester.enterText(find.byType(TextField).at(0), 'Siti');
    await tester.enterText(find.byType(TextField).at(1), 'siti@example.com');
    await tester.enterText(find.byType(TextField).at(2), 'rahasia123');
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.text('Email sudah digunakan.'), findsOneWidget);

    taken = false;
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(session.signedIn, isTrue);
  });
}
