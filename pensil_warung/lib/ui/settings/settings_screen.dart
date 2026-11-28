import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
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
      ],
    );
  }
}
