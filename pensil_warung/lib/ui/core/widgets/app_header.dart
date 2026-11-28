import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../data/session.dart';
import '../theme.dart';

/// Big title, optional subtitle, bell (unread dot) and avatar letter.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.avatar = false,
    this.hasUnread = false,
    this.onBell,
  });

  final String title;
  final String? subtitle;
  /// Show the avatar letter, which opens Pengaturan.
  final bool avatar;
  final bool hasUnread;
  final VoidCallback? onBell;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: appText(
                    30,
                    weight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: appText(14, color: AppColors.muted)),
              ],
            ),
          ),
          if (onBell != null)
            IconButton(
              tooltip: 'Notifikasi',
              onPressed: onBell,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none_rounded, size: 28),
                  if (hasUnread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.paper, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (avatar) const AvatarButton(),
        ],
      ),
    );
  }
}

/// Avatar letter of the signed-in user; opens Pengaturan.
class AvatarButton extends StatelessWidget {
  const AvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final name = context.select<Session, String>((s) => s.user?.username ?? '');
    return Semantics(
      button: true,
      label: 'Pengaturan',
      child: GestureDetector(
        onTap: () => context.push('/pengaturan'),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.avatar, shape: BoxShape.circle),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: appText(16, weight: FontWeight.w800, color: AppColors.surface)),
        ),
      ),
    );
  }
}

/// Back arrow + title for pushed screens.
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, required this.title, this.onBack, this.trailing, this.size = 20});

  final String title;
  final double size;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Kembali',
            onPressed: onBack ?? () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(title, style: appText(size, weight: FontWeight.w800)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
