import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:pensil_warung/data/prefs.dart';
import 'package:pensil_warung/ui/settings/display_settings.dart';
import 'package:pensil_warung/ui/settings/google_reauth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pensil_warung/data/api_exception.dart';
import 'package:pensil_warung/data/repositories/account_repository.dart';
import 'package:pensil_warung/data/repositories/broadcaster_repository.dart';
import 'package:pensil_warung/data/repositories/catat_repository.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/data/repositories/transaction_repository.dart';
import 'package:pensil_warung/ui/catat/catat_view_model.dart';
import 'package:pensil_warung/domain/broadcast.dart';
import 'package:pensil_warung/domain/user.dart';
import 'package:pensil_warung/data/session.dart';
import 'package:pensil_warung/routing/router.dart';
import 'package:pensil_warung/ui/broadcaster/broadcast_draft.dart';
import 'package:pensil_warung/ui/broadcaster/siaran_view_model.dart';
import 'package:pensil_warung/ui/broadcaster/tulis_screen.dart';
import 'package:pensil_warung/ui/core/widgets/main_nav.dart';
import 'package:provider/provider.dart';

import '../../support/feed.dart';

final _now = DateTime.utc(2026, 11, 28, 10); // 17.00 WIB

Map<String, Object?> _detail({
  int id = 5,
  String title = 'Judul',
  String status = 'scheduled',
  String shownAt = '2026-12-01T11:00:00Z', // 18.00 WIB
  String? body = 'Isi',
}) =>
    {
      'id': id,
      'category': 'info',
      'title': title,
      'summary': 'Ringkas',
      'has_body': body != null,
      'body': body,
      'shown_at': shownAt,
      'effective_status': status,
      'created_at': '2026-11-28T09:00:00Z',
      'created_by_name': 'Dina',
      'cancelled_at': null,
      'cancelled_by_name': null,
    };

class _Rig {
  _Rig({this.status = 200, Map<String, Object?>? reply}) : reply = reply ?? _detail() {
    api = ApiClient(
      baseUrl: 'http://x',
      client: MockClient((r) async {
        requests.add(r);
        final path = r.url.path;
        final body = path.endsWith('/broadcasts')
            ? r.method == 'GET'
                ? {'recipient_count': 12480, 'scheduled': [], 'sent': {'items': [], 'next_cursor': null}}
                : this.reply
            : status == 200
                ? this.reply
                : {'error': {'code': 'not_editable', 'message': 'Siaran sudah terkirim.'}};
        return http.Response(jsonEncode(body), r.method == 'POST' && path.endsWith('/broadcasts') ? 201 : status,
            headers: {'content-type': 'application/json'});
      }),
    );
    repo = BroadcasterRepository(api);
    list = SiaranViewModel(repo);
    draft = BroadcastDraft(repo, list, clock: () => _now);
  }

  final int status;
  final Map<String, Object?> reply;
  final requests = <http.Request>[];
  late final ApiClient api;
  late final BroadcasterRepository repo;
  late final SiaranViewModel list;
  late final BroadcastDraft draft;

  Map<String, dynamic> sentBody(String method) =>
      jsonDecode(requests.lastWhere((r) => r.method == method).body) as Map<String, dynamic>;
}

User _user(String role) => User(
      id: '1',
      displayName: 'Siti',
      username: 'siti',
      email: 's@x.id',
      role: role,
      permissions: const [],
      hasPassword: true,
    );

void main() {
  group('BroadcastDraft', () {
    test('send_at is RFC 3339 with +07:00 and the default is an hour ahead', () {
      final d = _Rig().draft;
      expect(d.date, '2026-11-28');
      expect(d.time, '18:00');
      d.update(date: '2026-12-01', time: '9.05');
      expect(d.sendAt, '2026-12-01T09:05:00+07:00');
      expect(d.at, DateTime.utc(2026, 12, 1, 2, 5));
      d.update(sendNow: true);
      expect(d.sendAt, isNull);
    });

    test('a past or malformed time is blocked locally and nothing is sent', () async {
      final rig = _Rig();
      final d = rig.draft..update(title: 'a', summary: 'b', date: '2026-11-28', time: '16:59');
      expect(d.whenError, pastTimeText);
      expect(await d.submit(), isNull);
      d.update(time: '25:00');
      expect(d.whenError, badTimeText);
      d.update(time: '17:01');
      expect(d.whenError, isNull);
      d.update(sendNow: true, time: 'abc');
      expect(d.whenError, isNull); // "now" ignores the time
      expect(rig.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    test('create sends the trimmed text, a null body and the WIB time', () async {
      final rig = _Rig();
      final d = rig.draft..update(title: ' Libur ', summary: 'Tetap jalan', date: '2026-12-01', time: '18:00');
      expect(await d.submit(), isNotNull);
      expect(rig.sentBody('POST'), {
        'category': 'info',
        'title': 'Libur',
        'summary': 'Tetap jalan',
        'body': null,
        'send_at': '2026-12-01T18:00:00+07:00',
      });
    });

    test('PATCH sends only what changed', () async {
      final rig = _Rig(reply: _detail(title: 'Baru'));
      final d = rig.draft..startEdit(Broadcast.fromJson(_detail()));
      expect(d.changes(), isEmpty);
      d.update(title: 'Baru');
      expect(d.changes(), {'title': 'Baru'});
      expect(await d.submit(), isNotNull);
      expect(rig.sentBody('PATCH'), {'title': 'Baru'}); // no send_at: the schedule stays
    });

    test('PATCH: a new time, "now" and a cleared body', () {
      final d = _Rig().draft..startEdit(Broadcast.fromJson(_detail()));
      d.update(time: '19:30');
      expect(d.changes(), {'send_at': '2026-12-01T19:30:00+07:00'});
      d.update(time: '18:00', body: '');
      expect(d.changes(), {'body': ''});
      d.update(sendNow: true);
      expect(d.changes(), {'body': '', 'send_at': null});
    });

    test('nothing changed: no request', () async {
      final rig = _Rig();
      final d = rig.draft..startEdit(Broadcast.fromJson(_detail()));
      expect(await d.submit(), isNotNull);
      expect(rig.requests.where((r) => r.method == 'PATCH'), isEmpty);
    });

    test('409 not_editable is kept so the screen can reload the broadcast', () async {
      final rig = _Rig(status: 409);
      final d = rig.draft..startEdit(Broadcast.fromJson(_detail()));
      d.update(title: 'Baru');
      expect(await d.submit(), isNull);
      expect((d.error as ApiException).code, 'not_editable');
      expect(d.editing!.id, 5);
    });

    test('server time_passed shows the same alert', () async {
      final rig = _Rig();
      final d = rig.draft..update(title: 'a', summary: 'b', time: '18:00');
      d.error = const ApiException(status: 422, code: 'time_passed', message: 'x');
      expect(d.whenError, pastTimeText);
    });
  });

  testWidgets('Tulis: Lanjut is disabled with the hint until title and summary are filled', (tester) async {
    tester.view.physicalSize = const Size(800, 2400); // the whole form is built
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final rig = _Rig();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: rig.list),
        ChangeNotifierProvider.value(value: rig.draft),
      ],
      child: const MaterialApp(home: Scaffold(body: TulisScreen())),
    ));
    expect(find.text('Isi judul dan ringkasan dulu'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'Libur');
    await tester.enterText(find.byType(TextField).at(1), 'Tetap jalan');
    await tester.pump();
    expect(find.text('Isi judul dan ringkasan dulu'), findsNothing);
    expect(find.text('5/60'), findsOneWidget);
    expect(find.text('11/120'), findsOneWidget);
  });

  group('router', () {
    Future<(GoRouter, Session)> boot(WidgetTester tester, String role, String at) async {
      final session = Session()..setUser(_user(role));
      final router = buildRouter(session, initialLocation: at);
      final rig = _Rig();
      final feed = await testFeed();
      final display = DisplaySettings(Prefs(await SharedPreferences.getInstance()));
      final products = ProductRepository(rig.api);
      final catat = CatatViewModel(CatatRepository(rig.api, products), products, TransactionRepository(rig.api, products));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: display),
          Provider(create: (_) => const GoogleReauth()),
          ChangeNotifierProvider.value(value: products),
          ChangeNotifierProvider.value(value: catat),
          ChangeNotifierProvider.value(value: session),
          Provider.value(value: rig.api),
          Provider(create: (_) => AccountRepository(rig.api)),
          Provider.value(value: rig.repo),
          ChangeNotifierProvider.value(value: rig.list),
          ChangeNotifierProvider.value(value: rig.draft),
          ChangeNotifierProvider.value(value: feed),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      return (router, session);
    }

    testWidgets('a broadcaster lands on the Siaran shell, a user on the user shell', (tester) async {
      final (r1, _) = await boot(tester, 'broadcaster', '/catat'); // a user path bounces to /tulis
      expect(r1.state.uri.path, '/tulis');
      final nav = tester.widget<MainNav>(find.byType(MainNav));
      expect(nav.items.map((i) => i.label), ['Siaran', 'Tulis', 'Akun']);
      expect(find.text('Siaran baru'), findsOneWidget);
      r1.go('/siaran');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ke semua pengguna · 12.480 akun'), findsOneWidget);
    });

    testWidgets('a user is kept in the user shell', (tester) async {
      final (r, _) = await boot(tester, 'user', '/siaran');
      expect(r.state.uri.path, '/catat');
      final nav = tester.widget<MainNav>(find.byType(MainNav));
      expect(nav.items.map((i) => i.label), ['Produk', 'Catat', 'Histori']);
    });

    testWidgets('a token swap keeps the navigation stack', (tester) async {
      final (r, session) = await boot(tester, 'broadcaster', '/akun');
      r.push('/pengaturan/username');
      await tester.pump(const Duration(milliseconds: 400));
      final before = r.state.uri.path;
      expect(before, '/pengaturan/username');
      session.replaceToken('new-token', _user('broadcaster')); // notifies after the storage write, which pump flushes
      await tester.pump(const Duration(milliseconds: 400));
      expect(r.state.uri.path, before);
      expect(r.canPop(), isTrue); // the stack under it is still there
    });
  });
}
