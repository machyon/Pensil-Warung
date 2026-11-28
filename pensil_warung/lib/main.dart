import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/api_client.dart';
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

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.session),
        Provider.value(value: widget.api),
      ],
      child: MaterialApp.router(
        title: 'Pensil Warung',
        theme: buildTheme(),
        routerConfig: _router,
      ),
    );
  }
}
