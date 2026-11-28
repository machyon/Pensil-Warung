import 'package:material_ui/material_ui.dart';

import '../../domain/broadcast.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/category_icon.dart';

/// Header of the pushed broadcaster pages: bordered back button, title and a subtitle.
class SiaranHeader extends StatelessWidget {
  const SiaranHeader({super.key, required this.title, required this.subtitle, required this.onBack});

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 20, 8),
        child: Row(children: [
          Semantics(
            button: true,
            label: 'Kembali',
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.fieldBorder),
                ),
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: appText(26, weight: FontWeight.w800, letterSpacing: -0.5)),
              Text(subtitle, style: appText(14, weight: FontWeight.w500, color: AppColors.muted)),
            ]),
          ),
        ]),
      );
}

/// One row of a Siaran list: category badge, title, "Info · Hari ini, 18.00" and an optional countdown pill.
class BroadcastRow extends StatelessWidget {
  const BroadcastRow({super.key, required this.b, required this.onTap, this.countdown = false});

  final Broadcast b;
  final VoidCallback onTap;
  final bool countdown;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            CategoryBadge(b.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.title, style: appText(16, weight: FontWeight.w700).copyWith(height: 22 / 16)),
                const SizedBox(height: 4),
                Text('${b.categoryLabel} · ${wibRelative(b.shownAt)}', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
              ]),
            ),
            if (countdown)
              Container(
                padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.schedule_rounded, size: 15, color: AppColors.onAccent),
                  const SizedBox(width: 4),
                  Text(untilText(b.shownAt), style: appText(13, weight: FontWeight.w800, color: AppColors.onAccent)),
                ]),
              ),
          ]),
        ),
      );
}
