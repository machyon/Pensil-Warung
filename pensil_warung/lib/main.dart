import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/api_client.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/catat_repository.dart';
import 'ui/catat/catat_view_model.dart';
import 'data/repositories/product_repository.dart';
import 'data/session.dart';
import 'routing/router.dart';
import 'ui/core/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  checkConfig();
  final session = Session();
  final api = ApiClient(token: () => session.token, onUnauthorized: session.signOut);
  runApp(MyApp(session: session, api: api));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.session, required this.api});

  final Session session;
  final ApiClient api;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final _router = buildRouter(widget.session);
  late final _products = ProductRepository(widget.api);
  late final _catat = CatatViewModel(CatatRepository(widget.api, _products), _products);

  void _onSession() {
    if (!widget.session.signedIn) {
      _products.clear();
      _catat.clear();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
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
        ChangeNotifierProvider.value(value: _products),
        ChangeNotifierProvider.value(value: _catat),
        Provider(create: (_) => CatatRepository(widget.api, _products)),
      ],
      child: MaterialApp.router(
        title: 'Pensil Warung',
        theme: buildTheme(),
        routerConfig: _router,
      ),
    );
  }
}
