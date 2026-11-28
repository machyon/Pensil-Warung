import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:pensil_warung/data/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pensil_warung/data/repositories/catat_repository.dart';
import 'package:pensil_warung/data/repositories/transaction_repository.dart';
import 'package:pensil_warung/data/repositories/product_repository.dart';
import 'package:pensil_warung/ui/catat/catat_view_model.dart';
import 'package:pensil_warung/data/repositories/auth_repository.dart';
import 'package:pensil_warung/data/session.dart';
import 'package:pensil_warung/domain/user.dart';
import 'package:pensil_warung/routing/router.dart';
import 'package:pensil_warung/ui/core/widgets/main_nav.dart';

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
  group('redirectFor', () {
    test('no session goes to /welcome', () {
      expect(redirectFor(null, '/catat'), '/welcome');
      expect(redirectFor(null, '/welcome'), isNull);
    });
    test('splash is left alone', () {
      expect(redirectFor(null, '/'), isNull);
      expect(redirectFor(_user('user'), '/'), isNull);
    });
    test('user is kept in user tabs', () {
      final u = _user('user');
      expect(redirectFor(u, '/produk'), isNull);
      expect(redirectFor(u, '/siaran'), '/catat');
      expect(redirectFor(u, '/welcome'), '/catat');
    });
    test('broadcaster is kept in broadcaster tabs', () {
      final b = _user('broadcaster');
      expect(redirectFor(b, '/akun'), isNull);
      expect(redirectFor(b, '/catat'), '/tulis');
    });
  });

  testWidgets('user shell shows the nav; no session shows Landing', (tester) async {
    final session = Session()..setUser(_user('user'));
    final router = buildRouter(session, initialLocation: '/catat');
    final api = ApiClient(
        baseUrl: 'http://x', client: MockClient((_) async => http.Response('{"items":[]}', 200)));
    final products = ProductRepository(api);
    final catat = CatatViewModel(CatatRepository(api, products), products, TransactionRepository(api, products));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider.value(value: products),
        ChangeNotifierProvider.value(value: catat),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(MainNav), findsOneWidget);

    router.go('/welcome'); // signed in: bounced back to the user's home
    await tester.pumpAndSettle();
    expect(find.byType(MainNav), findsOneWidget);
    expect(find.text('Landing'), findsNothing);
  });

  testWidgets('without a session a tab path shows Landing', (tester) async {
    final session = Session();
    final router = buildRouter(session, initialLocation: '/catat');
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        Provider(create: (_) => AuthRepository(ApiClient(baseUrl: 'http://x'))),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mulai sekarang'), findsOneWidget);
    expect(find.byType(MainNav), findsNothing);
  });
}
