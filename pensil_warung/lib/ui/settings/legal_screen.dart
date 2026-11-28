import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import 'legal_text.dart';
import 'settings_widgets.dart';

/// [10g] Syarat & Ketentuan / Kebijakan Privasi: one layout, the title picks the text.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.sections});

  final String title;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final keys = [for (final _ in sections) GlobalKey()];
    return SettingsPage(
      title: title,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Berlaku sejak $legalEffectiveDate', style: appText(14, color: AppColors.muted)),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('ISI', style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
            ),
            for (var i = 0; i < sections.length; i++)
              InkWell(
                onTap: () => Scrollable.ensureVisible(keys[i].currentContext!, duration: const Duration(milliseconds: 250)),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('${i + 1}. ${sections[i].title}', style: appText(15, weight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
        AppCard(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: 20),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 20),
              ],
              Column(
                key: keys[i],
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}. ${sections[i].title}', style: appText(18, weight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(sections[i].body, style: appText(16).copyWith(height: 26 / 16)),
                ],
              ),
            ],
          ]),
        ),
      ],
    );
  }
}
