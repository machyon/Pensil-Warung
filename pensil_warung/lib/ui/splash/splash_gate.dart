import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/api_client.dart';
import '../../data/api_exception.dart';
import '../../data/session.dart';
import '../../domain/user.dart';
import '../../routing/router.dart';
import '../../splash_screen.dart';
import '../core/widgets/error_view.dart';

/// Shows the splash for at least its 1 s intro while it pings `/health` and,
/// with a stored token, loads `/me`; then routes by session.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final api = context.read<ApiClient>();
    final session = context.read<Session>();
    setState(() => _error = null);
    try {
      await Future.wait([
        Future<void>.delayed(const Duration(seconds: 1)),
        _load(api, session),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    if (mounted) context.go(homePath(session.user));
  }

  Future<void> _load(ApiClient api, Session session) async {
    await session.restore();
    await api.get('/health');
    if (session.token == null) return;
    try {
      final me = await api.get('/api/v1/me') as Map<String, dynamic>;
      session.setUser(User.fromJson(me));
    } on ApiException catch (e) {
      // 401 / account_gone already cleared the session via ApiClient.onUnauthorized.
      if (e.status != 401) rethrow;
      if (session.token != null) await session.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error == null) return const SplashScreen();
    if (kDebugMode && error is! ApiException && error is! NetworkException) {
      debugPrint('splash failed: $error');
    }
    return Scaffold(body: SafeArea(child: ErrorView(error: error, onRetry: _start)));
  }
}
