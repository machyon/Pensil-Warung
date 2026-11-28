import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Big title, optional subtitle, bell (unread dot) and avatar letter.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.avatarLetter,
    this.hasUnread = false,
    this.onBell,
    this.onAvatar,
  });

  final String title;
  final String? subtitle;
  final String? avatarLetter;
  final bool hasUnread;
  final VoidCallback? onBell;
  final VoidCallback? onAvatar;

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
                Text(title, style: appText(30, weight: FontWeight.w800, letterSpacing: -0.5)),
                if (subtitle != null) Text(subtitle!, style: appText(14, color: AppColors.muted)),
              ],
            ),
          ),
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
          if (avatarLetter != null)
            Semantics(
              button: true,
              label: 'Pengaturan',
              child: GestureDetector(
                onTap: onAvatar,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.avatar, shape: BoxShape.circle),
                  child: Text(avatarLetter!.toUpperCase(),
                      style: appText(16, weight: FontWeight.w800, color: AppColors.surface)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Back arrow + title for pushed screens.
class BackHeader extends StatelessWidget {
  const BackHeader({super.key, required this.title, this.onBack});

  final String title;
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
          Expanded(child: Text(title, style: appText(20, weight: FontWeight.w800))),
        ],
      ),
    );
  }
}
