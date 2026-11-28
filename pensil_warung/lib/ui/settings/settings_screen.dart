import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import '../core/widgets/segmented_tabs.dart';
import 'display_settings.dart';
import 'settings_widgets.dart';

/// [10] Pengaturan. Opened from the avatar of any header.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<Session>();
      try {
        session.setUser(await context.read<AccountRepository>().me());
      } catch (_) {} // the cached user stays; a 401 is handled by ApiClient
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    if (user == null) return const SizedBox.shrink();
    final display = context.watch<DisplaySettings>();
    return SettingsPage(
      title: 'Pengaturan',
      titleSize: 30,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(children: [
            Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.avatar,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.paper, spreadRadius: 6)],
              ),
              child: Text(user.username[0].toUpperCase(), style: appText(48, weight: FontWeight.w800, color: AppColors.surface)),
            ),
            const SizedBox(height: 16),
            Text(user.username, textAlign: TextAlign.center, style: appText(26, weight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            Text(user.email, textAlign: TextAlign.center, style: appText(16, color: AppColors.muted)),
          ]),
        ),
        SettingsSection(title: 'Akun', children: [
          SettingsRow(
              icon: Icons.person_outline_rounded,
              label: 'Username',
              value: user.username,
              onTap: () => context.push('/pengaturan/username')),
          SettingsRow(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              value: user.email,
              onTap: user.hasPassword ? () => context.push('/pengaturan/email') : null),
          if (user.hasPassword)
            SettingsRow(
                icon: Icons.lock_outline_rounded,
                label: 'Kata sandi',
                value: '••••••••',
                onTap: () => context.push('/pengaturan/sandi')),
        ]),
        SettingsSection(title: 'Tampilan', children: [
          _Choice(
              icon: Icons.contrast_rounded,
              label: 'Tema',
              labels: DisplaySettings.temaLabels,
              selected: display.tema,
              onChanged: display.setTema),
          _Choice(
              icon: Icons.text_fields_rounded,
              label: 'Ukuran tulisan',
              labels: DisplaySettings.textSizeLabels,
              selected: display.textSize,
              onChanged: display.setTextSize),
        ]),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.label, required this.labels, required this.selected, required this.onChanged});

  final IconData icon;
  final String label;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            RowIcon(icon),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: appText(16, weight: FontWeight.w700))),
          ]),
          const SizedBox(height: 12),
          SegmentedTabs(labels: labels, selected: selected, onChanged: onChanged, yellow: true),
        ]),
      );
}
