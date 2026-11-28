import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/session.dart';
import '../domain/user.dart';
import '../ui/core/widgets/main_nav.dart';
import '../ui/core/widgets/placeholder_tab.dart';
import '../ui/landing/landing_screen.dart';
import '../ui/splash/splash_gate.dart';

const _userTabs = ['/produk', '/catat', '/histori'];
const _broadcasterTabs = ['/siaran', '/tulis', '/akun'];

/// Where a signed-in user lands; Landing without one.
String homePath(User? user) => user == null
    ? '/welcome'
    : user.isBroadcaster
        ? '/tulis'
        : '/catat';

/// Pure redirect rule, split out so it can be tested.
String? redirectFor(User? user, String path) {
  if (path == '/') return null; // SplashGate routes itself once it has loaded the session
  if (user == null) return path == '/welcome' ? null : '/welcome';
  final tabs = user.isBroadcaster ? _broadcasterTabs : _userTabs;
  return tabs.any(path.startsWith) ? null : homePath(user);
}

GoRouter buildRouter(Session session, {String initialLocation = '/'}) {
  StatefulShellRoute shell(List<String> tabs, List<String> titles, List<NavItem> items) {
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
            GoRoute(path: tabs[i], builder: (_, _) => PlaceholderTab(titles[i])),
          ]),
      ],
    );
  }

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: session,
    redirect: (context, state) => redirectFor(session.user, state.uri.path),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashGate()),
      GoRoute(path: '/welcome', builder: (_, _) => const LandingScreen()),
      shell(_userTabs, ['Produk', 'Catat', 'Histori'], userNavItems),
      shell(_broadcasterTabs, ['Siaran', 'Tulis', 'Akun'], broadcasterNavItems),
    ],
  );
}
