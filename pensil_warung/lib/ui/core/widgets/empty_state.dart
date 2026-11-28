import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'buttons.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.actionLabel,
    this.onAction,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String? text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: appText(20, weight: FontWeight.w800)),
            if (text != null) ...[
              const SizedBox(height: 8),
              Text(text!, textAlign: TextAlign.center, style: appText(15, color: AppColors.muted)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 24),
              SizedBox(width: 220, child: PrimaryButton(label: actionLabel!, onPressed: onAction)),
            ],
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ],
        ),
      ),
    );
  }
}
