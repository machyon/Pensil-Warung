import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/account_repository.dart';
import '../../data/session.dart';
import '../core/theme.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/segmented_tabs.dart';
import '../catat/catat_view_model.dart';
import 'google_reauth.dart';
import 'display_settings.dart';
import 'settings_widgets.dart';

/// [10] Pengaturan. Opened from the avatar of any header.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.tab = false});

  /// The broadcaster's Akun tab: same rows, no back arrow.
  final bool tab;

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
      title: widget.tab ? 'Akun' : 'Pengaturan',
      titleSize: 30,
      tab: widget.tab,
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
            if (user.isBroadcaster) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.campaign_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('Penyiar', style: appText(13, weight: FontWeight.w800)),
                ]),
              ),
            ],
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
        SettingsSection(title: 'Bantuan', children: [
          SettingsRow(icon: Icons.info_outline_rounded, label: 'Tentang Pensil Warung', onTap: () => context.push('/pengaturan/tentang')),
        ]),
        SettingsSection(title: 'Legal', children: [
          SettingsRow(icon: Icons.description_outlined, label: 'Syarat & Ketentuan', onTap: () => context.push('/pengaturan/syarat')),
          SettingsRow(icon: Icons.verified_user_outlined, label: 'Kebijakan Privasi', onTap: () => context.push('/pengaturan/privasi')),
        ]),
        _Tile(
          height: 56,
          label: 'Keluar',
          icon: Icons.logout_rounded,
          border: true,
          onTap: () => _confirmSignOut(context),
        ),
        if (!user.isBroadcaster)
          _Tile(height: 48, label: 'Hapus akun', icon: Icons.delete_outline_rounded, onTap: () => context.push('/pengaturan/hapus')),
      ],
    );
  }
}

Future<void> _confirmSignOut(BuildContext context) async {
  final unsaved = context.read<CatatViewModel>().unsavedLines;
  final session = context.read<Session>();
  final google = context.read<GoogleReauth>();
  final ok = await showAppSheet<bool>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: const Icon(Icons.logout_rounded, color: Color(0xFFB3261E)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Keluar dari akun?', style: appText(22, weight: FontWeight.w800, letterSpacing: -0.4).copyWith(height: 28 / 22)),
              const SizedBox(height: 4),
              Text('Jualan yang sudah disimpan tetap aman. Catatan yang belum disimpan di HP ini akan hilang.',
                  style: appText(14, color: AppColors.label).copyWith(height: 20 / 14)),
            ]),
          ),
        ]),
        if (unsaved > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.edit_note_rounded, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('$unsaved baris di Catat belum disimpan', style: appText(13, weight: FontWeight.w600))),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: SecondaryButton(label: 'Batal', onPressed: () => Navigator.pop(context, false))),
          const SizedBox(width: 12),
          Expanded(child: DangerButton(label: 'Keluar', onPressed: () => Navigator.pop(context, true))),
        ]),
      ],
    ),
  );
  if (ok != true) return;
  await google.signOut();
  await session.signOut(); // the router leaves for Landing
}

class _Tile extends StatelessWidget {
  const _Tile({required this.height, required this.label, required this.icon, required this.onTap, this.border = false});

  final double height;
  final String label;
  final IconData icon;
  final bool border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: border ? AppColors.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: border ? const BorderSide(color: AppColors.border) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: border ? 20 : 18, color: const Color(0xFFB3261E)),
              SizedBox(width: border ? 10 : 8),
              Text(label, style: appText(border ? 17 : 15, weight: FontWeight.w700, color: const Color(0xFFB3261E))),
            ]),
          ),
        ),
      );
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
