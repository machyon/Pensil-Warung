import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/session.dart';
import '../domain/user.dart';
import '../ui/core/widgets/main_nav.dart';
import '../ui/core/widgets/placeholder_tab.dart';
import '../ui/auth/login_screen.dart';
import '../ui/auth/register_screen.dart';
import '../ui/landing/landing_screen.dart';
import '../ui/catat/catat_screen.dart';
import '../ui/histori/day_list_screen.dart';
import '../ui/histori/histori_screen.dart';
import '../ui/products/product_list_screen.dart';
import '../ui/products/product_routes.dart';
import '../ui/splash/splash_gate.dart';

const _userTabs = ['/produk', '/catat', '/histori'];
const _broadcasterTabs = ['/siaran', '/tulis', '/akun'];

/// Full-screen history screens, pushed over any tab (Catat links to a Detail too).
const _userExtras = ['/hari', '/transaksi'];

const _publicPaths = ['/welcome', '/masuk', '/daftar'];

/// Where a signed-in user lands; Landing without one.
String homePath(User? user) => user == null
    ? '/welcome'
    : user.isBroadcaster
        ? '/tulis'
        : '/catat';

/// Pure redirect rule, split out so it can be tested.
String? redirectFor(User? user, String path) {
  if (path == '/') return null; // SplashGate routes itself once it has loaded the session
  if (user == null) return _publicPaths.contains(path) ? null : '/welcome';
  final tabs = user.isBroadcaster ? _broadcasterTabs : _userTabs;
  if (!user.isBroadcaster && _userExtras.any(path.startsWith)) return null;
  return tabs.any(path.startsWith) ? null : homePath(user);
}

final rootKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(Session session, {String initialLocation = '/'}) {
  StatefulShellRoute shell(List<String> tabs, List<String> titles, List<NavItem> items,
      {Map<int, Widget> screens = const {}, Map<int, List<RouteBase>> subRoutes = const {}}) {
    return StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => Scaffold(
        body: navigationShell,
        bottomNavigationBar: MainNav(
          items: items,
          selected: navigationShell.currentIndex,
          onTap: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
        ),
      ),
      branches: [
        for (var i = 0; i < tabs.length; i++)
          StatefulShellBranch(routes: [
            GoRoute(
              path: tabs[i],
              builder: (_, _) => screens[i] ?? PlaceholderTab(titles[i]),
              routes: subRoutes[i] ?? const [],
            ),
          ]),
      ],
    );
  }

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    refreshListenable: session,
    redirect: (context, state) => redirectFor(session.user, state.uri.path),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashGate()),
      GoRoute(path: '/welcome', builder: (_, _) => const LandingScreen()),
      GoRoute(path: '/masuk', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/daftar', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/hari/:date', parentNavigatorKey: rootKey, builder: (_, s) => DayListScreen(date: s.pathParameters['date']!)),
      shell(
        _userTabs,
        ['Produk', 'Catat', 'Histori'],
        userNavItems,
        screens: {0: const ProductListScreen(), 1: const CatatScreen(), 2: const HistoriScreen()},
        subRoutes: {0: productRoutes},
      ),
      shell(_broadcasterTabs, ['Siaran', 'Tulis', 'Akun'], broadcasterNavItems),
    ],
  );
}
