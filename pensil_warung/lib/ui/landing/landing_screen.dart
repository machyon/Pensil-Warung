import 'package:material_ui/material_ui.dart';

import '../core/widgets/app_header.dart';

/// Placeholder until branch 02 builds the real Landing.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(children: [AppHeader(title: 'Landing')]),
      ),
    );
  }
}
