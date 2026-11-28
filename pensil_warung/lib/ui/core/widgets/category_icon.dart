import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Icon for a broadcast `category` (`update`, `berita`, `tips`, else info).
IconData categoryIcon(String category) => switch (category) {
      'update' => Icons.system_update_alt_rounded,
      'berita' => Icons.campaign_outlined,
      'tips' => Icons.lightbulb_outline_rounded,
      _ => Icons.info_outline_rounded,
    };

/// The 44 px grey square with a category icon, as in the notification list.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key});

  final String category;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14)),
        child: Icon(categoryIcon(category), size: 22, color: AppColors.label),
      );
}
