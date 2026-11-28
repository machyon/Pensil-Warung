import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';

/// Pushed settings screen: back header, scrolling body, optional action bar at the bottom.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children, this.bottom, this.titleSize = 26});

  final String title;
  final double titleSize;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BackHeader(title: title, size: titleSize),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 16), children[i]],
                  ],
                ),
              ),
            ),
            if (bottom != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}

/// "Akun" style group: small caps title above a card of rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(title!.toUpperCase(), style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
          ),
          const SizedBox(height: 8),
        ],
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.border),
              children[i],
            ],
          ]),
        ),
      ],
    );
  }
}

class RowIcon extends StatelessWidget {
  const RowIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: AppColors.label),
      );
}

/// Icon, label, optional value, chevron when [onTap] is set.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, this.icon, required this.label, this.value, this.onTap});

  final IconData? icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            if (icon != null) ...[RowIcon(icon!), const SizedBox(width: 14)],
            Expanded(child: Text(label, style: appText(16, weight: FontWeight.w700))),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(value!, overflow: TextOverflow.ellipsis, style: appText(15, color: AppColors.muted)),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.faint),
            ],
          ]),
        ),
      ),
    );
  }
}

/// White card the form fields sit in.
class FormCard extends StatelessWidget {
  const FormCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
          ],
        ),
      );
}

/// Info icon and a short note under a form card.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.label),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: appText(14, color: AppColors.label).copyWith(height: 20 / 14))),
        ]),
      );
}
