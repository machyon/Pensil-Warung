import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'buttons.dart';

/// Bottom sheet used by every confirm. Returns what the sheet pops with.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.fieldBorder, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            builder(context),
          ],
        ),
      ),
    ),
  );
}

/// Yes/no confirm. True when the user confirms.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  String? text,
  String confirmLabel = 'Ya',
  String cancelLabel = 'Batal',
}) async {
  final ok = await showAppSheet<bool>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: appText(20, weight: FontWeight.w800)),
        if (text != null) ...[
          const SizedBox(height: 8),
          Text(text, style: appText(15, color: AppColors.muted)),
        ],
        const SizedBox(height: 20),
        PrimaryButton(label: confirmLabel, onPressed: () => Navigator.pop(context, true)),
        const SizedBox(height: 10),
        SecondaryButton(label: cancelLabel, onPressed: () => Navigator.pop(context, false)),
      ],
    ),
  );
  return ok ?? false;
}
