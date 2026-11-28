import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'data/api_client.dart';
import 'data/prefs.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/broadcast_repository.dart';
import 'data/repositories/catat_repository.dart';
import 'ui/catat/catat_view_model.dart';
import 'data/repositories/analytics_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/session.dart';
import 'routing/router.dart';
import 'ui/core/theme.dart';
import 'ui/notifications/notification_feed.dart';
import 'ui/settings/display_settings.dart';
import 'ui/settings/google_reauth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  checkConfig();
  final prefs = Prefs(await SharedPreferences.getInstance());
  final session = Session();
  final api = ApiClient(token: () => session.token, onUnauthorized: session.signOut);
  runApp(MyApp(session: session, api: api, prefs: prefs));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.session, required this.api, required this.prefs});

  final Session session;
  final ApiClient api;
  final Prefs prefs;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final _display = DisplaySettings(widget.prefs);
  late final _router = buildRouter(widget.session);
  late final _products = ProductRepository(widget.api);
  late final _transactions = TransactionRepository(widget.api, _products);
  late final _feed = NotificationFeed(BroadcastRepository(widget.api), widget.prefs);
  late final _catat = CatatViewModel(CatatRepository(widget.api, _products), _products, _transactions);

  void _onSession() {
    if (!widget.session.signedIn) {
      _products.clear();
      _catat.clear();
      _feed.clear();
    } else if (!_feed.loaded) {
      _feed.load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.session.signedIn) _feed.load();
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    WidgetsBinding.instance.addObserver(this);
    if (widget.session.signedIn) _feed.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSession);
    _feed.dispose();
    _display.dispose();
    _catat.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.session),
        Provider.value(value: widget.api),
        Provider(create: (_) => AuthRepository(widget.api)),
        Provider(create: (_) => AccountRepository(widget.api)),
        Provider(create: (_) => const GoogleReauth()),
        ChangeNotifierProvider.value(value: _products),
        ChangeNotifierProvider.value(value: _transactions),
        Provider(create: (_) => AnalyticsRepository(widget.api)),
        ChangeNotifierProvider.value(value: _catat),
        ChangeNotifierProvider.value(value: _feed),
        ChangeNotifierProvider.value(value: _display),
        Provider(create: (_) => CatatRepository(widget.api, _products)),
      ],
      child: MaterialApp.router(
        title: 'Pensil Warung',
        theme: buildTheme(),
        routerConfig: _router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: context.watch<DisplaySettings>().textScaler),
          child: child!,
        ),
      ),
    );
  }
}
