import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/prefs.dart';
import 'package:pensil_warung/data/repositories/account_repository.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/data/session.dart';
import 'package:pensil_warung/domain/user.dart';
import 'package:pensil_warung/ui/settings/account_view_model.dart';
import 'package:pensil_warung/ui/settings/delete_account_screen.dart';
import 'package:pensil_warung/ui/settings/display_settings.dart';
import 'package:pensil_warung/ui/settings/google_reauth.dart';
import 'package:pensil_warung/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pensil_warung/ui/catat/catat_view_model.dart';
import 'package:pensil_warung/data/repositories/catat_repository.dart';
import 'package:pensil_warung/data/repositories/transaction_repository.dart';

Map<String, Object?> _user({bool hasPassword = true}) => {
      'id': 'u1',
      'display_name': 'Siti',
      'username': 'siti',
      'email': 'siti@x.id',
      'role': 'user',
      'permissions': <String>[],
      'has_password': hasPassword,
    };

class _FakeGoogle extends GoogleReauth {
  _FakeGoogle(this.token);
  final String? token;
  bool signedOut = false;

  @override
  Future<String?> idToken() async => token;

  @override
  Future<void> signOut() async => signedOut = true;
}

class _Env {
  _Env(this.session, this.account, this.requests, this.google);
  final Session session;
  final AccountRepository account;
  final List<http.Request> requests;
  final _FakeGoogle google;
}

_Env _env(Future<http.Response> Function(http.Request) reply, {bool hasPassword = true, String? idToken}) {
  FlutterSecureStorage.setMockInitialValues({});
  final session = Session()..setUser(User.fromJson({..._user(hasPassword: hasPassword)}));
  final requests = <http.Request>[];
  final api = ApiClient(
    baseUrl: 'http://x',
    token: () => session.token,
    onUnauthorized: session.signOut,
    client: MockClient((r) async {
      requests.add(r);
      return reply(r);
    }),
  );
  return _Env(session, AccountRepository(api), requests, _FakeGoogle(idToken));
}

http.Response _json(int status, Object? body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<void> _pump(WidgetTester tester, _Env env, Widget home, {ProductRepository? products, Prefs? prefs}) async {
  tester.view.physicalSize = const Size(412, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final p = prefs ?? Prefs(await SharedPreferences.getInstance());
  final productRepo = products ?? ProductRepository(ApiClient(baseUrl: 'http://x', client: MockClient((_) async => _json(200, {'items': [], 'count': 0}))));
  final catat = CatatViewModel(
      CatatRepository(ApiClient(baseUrl: 'http://x'), productRepo), productRepo, TransactionRepository(ApiClient(baseUrl: 'http://x'), productRepo));
  addTearDown(catat.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: env.session),
      Provider.value(value: env.account),
      Provider<GoogleReauth>.value(value: env.google),
      ChangeNotifierProvider.value(value: productRepo),
      ChangeNotifierProvider.value(value: catat),
      ChangeNotifierProvider(create: (_) => DisplaySettings(p)),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('password change swaps the token and keeps the session signed in', () async {
    final env = _env((r) async => _json(200, {'token': 'new-token', 'user': _user()}));
    await env.session.signIn('old-token', User.fromJson(_user()));
    final ok = await PasswordViewModel(env.account, env.session).save('rahasia123', 'rahasia456');
    expect(ok, isTrue);
    expect(env.session.token, 'new-token');
    expect(env.session.signedIn, isTrue);
    expect(env.requests.single.method, 'PUT');
    expect(env.requests.single.headers['Authorization'], 'Bearer old-token');
  });

  test('wrong current password shows under that field and keeps the old token', () async {
    final env = _env((r) async => _json(401, {'error': {'code': 'invalid_credentials', 'message': 'x'}}));
    await env.session.signIn('old-token', User.fromJson(_user()));
    final vm = PasswordViewModel(env.account, env.session);
    expect(await vm.save('salah', 'rahasia456'), isFalse);
    expect(vm.currentError, 'Kata sandi salah');
    expect(env.session.token, 'old-token');
  });

  test('email change swaps the token; username_taken maps to its message', () async {
    final env = _env((r) async => r.url.path.endsWith('username')
        ? _json(409, {'error': {'code': 'username_taken', 'message': 'x'}})
        : _json(200, {'token': 'tok2', 'user': {..._user(), 'email': 'baru@x.id'}}));
    await env.session.signIn('tok1', User.fromJson(_user()));
    expect(await EmailViewModel(env.account, env.session).save('baru@x.id', 'rahasia123'), isTrue);
    expect(env.session.token, 'tok2');
    expect(env.session.user!.email, 'baru@x.id');
    final u = UsernameViewModel(env.account, env.session);
    expect(await u.save('dev'), isFalse);
    expect(u.usernameError, 'Username sudah dipakai');
    expect(UsernameViewModel.valid.hasMatch('ab'), isFalse);
    expect(UsernameViewModel.valid.hasMatch('a' * 30), isTrue);
    expect(UsernameViewModel.valid.hasMatch('a' * 31), isFalse);
  });

  testWidgets('Google-only: no Kata sandi row and the email row has no link', (tester) async {
    final env = _env((r) async => _json(200, _user(hasPassword: false)), hasPassword: false);
    await _pump(tester, env, const SettingsScreen());
    expect(find.text('Kata sandi'), findsNothing);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('siti@x.id'), findsWidgets);
    final emailRow = find.ancestor(of: find.text('Email'), matching: find.byType(InkWell)).first;
    expect(tester.widget<InkWell>(emailRow).onTap, isNull);
  });

  testWidgets('password user sees Kata sandi and a linked email row', (tester) async {
    final env = _env((r) async => _json(200, _user()));
    await _pump(tester, env, const SettingsScreen());
    expect(find.text('Kata sandi'), findsOneWidget);
    final emailRow = find.ancestor(of: find.text('Email'), matching: find.byType(InkWell)).first;
    expect(tester.widget<InkWell>(emailRow).onTap, isNotNull);
  });

  testWidgets('text size Besar scales the text and is saved; Keluar shows the unsaved lines', (tester) async {
    final env = _env((r) async => _json(200, _user()));
    SharedPreferences.setMockInitialValues({});
    final prefs = Prefs(await SharedPreferences.getInstance());
    await _pump(tester, env, const SettingsScreen(), prefs: prefs);
    await tester.scrollUntilVisible(find.text('Besar'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Besar'));
    await tester.pump();
    final display = tester.element(find.byType(SettingsScreen)).read<DisplaySettings>();
    expect(display.textScaler.scale(10), closeTo(12, 0.001));
    expect(prefs.textSize, 2);
    display.setTextSize(0);
    expect(display.textScaler.scale(10), closeTo(9, 0.001));

    final catat = tester.element(find.byType(SettingsScreen)).read<CatatViewModel>();
    catat.controller.text = 'kopi 2\nteh 1\n\n';
    await tester.scrollUntilVisible(find.text('Keluar'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('2 baris di Catat belum disimpan'), findsOneWidget);
    await tester.tap(find.text('Keluar').last);
    await tester.pumpAndSettle();
    expect(env.session.user, isNull);
    expect(env.google.signedOut, isTrue);
  });

  testWidgets('Hapus akun needs the checkbox and a password; 204 signs out', (tester) async {
    final env = _env((r) async => http.Response('', 204));
    await _pump(tester, env, const DeleteAccountScreen());
    await tester.enterText(find.byType(TextField), 'rahasia123');
    await tester.pump();
    await tester.tap(find.text('Hapus akun').last);
    await tester.pumpAndSettle();
    expect(find.text('Hapus permanen'), findsNothing); // checkbox not ticked: button disabled
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Hapus akun').last);
    await tester.pumpAndSettle();
    expect(find.text('Hapus permanen'), findsOneWidget);
    await tester.tap(find.text('Hapus permanen'));
    await tester.pumpAndSettle();
    expect(env.requests.single.method, 'DELETE');
    expect(jsonDecode(env.requests.single.body), {'current_password': 'rahasia123'});
    expect(env.session.user, isNull);
  });

  testWidgets('Hapus akun, Google-only: re-auth sends the id_token; reauth_required keeps the screen', (tester) async {
    var stale = true;
    final env = _env((r) async => stale
        ? _json(401, {'error': {'code': 'reauth_required', 'message': 'x'}})
        : http.Response('', 204), hasPassword: false, idToken: 'g-token');
    await _pump(tester, env, const DeleteAccountScreen());
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Masuk ulang dengan Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus akun').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus permanen'));
    await tester.pumpAndSettle();
    expect(jsonDecode(env.requests.single.body), {'id_token': 'g-token'});
    expect(find.text('Masuk ulang dengan Google dulu.'), findsOneWidget);
    expect(env.session.user, isNotNull);

    stale = false;
    await tester.tap(find.text('Masuk ulang dengan Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus akun').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus permanen'));
    await tester.pumpAndSettle();
    expect(env.session.user, isNull);
  });
}
