import 'package:material_ui/material_ui.dart';

import 'app_header.dart';

/// Stand-in for a tab until its branch lands.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [AppHeader(title: title)],
      ),
    );
  }
}
