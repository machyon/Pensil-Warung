import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../domain/broadcast.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/error_view.dart';
import 'notification_feed.dart';

/// [32b] Notifikasi / [32] NotifikasiKosong. Pushed over the tabs from the bell.
class NotifikasiScreen extends StatefulWidget {
  const NotifikasiScreen({super.key});

  @override
  State<NotifikasiScreen> createState() => _NotifikasiScreenState();
}

class _NotifikasiScreenState extends State<NotifikasiScreen> {
  bool _onlyUnread = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<NotificationFeed>().load());
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<NotificationFeed>();
    final shown = _onlyUnread ? feed.unread : feed.items;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(subtitle: feed.unreadCount > 0 ? '${feed.unreadCount} belum dibaca' : feed.items.isEmpty ? 'Belum ada' : 'Semua sudah dibaca'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _Filter(selectedUnread: _onlyUnread, onChanged: (v) => setState(() => _onlyUnread = v)),
            ),
            Expanded(child: _content(feed, shown)),
          ],
        ),
      ),
    );
  }

  Widget _content(NotificationFeed feed, List<Broadcast> shown) {
    if (feed.error != null && !feed.loaded) return ErrorView(error: feed.error!, onRetry: feed.load);
    if (!feed.loaded) return const Center(child: CircularProgressIndicator());
    if (feed.items.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'Belum ada notifikasi',
        text: 'Pembaruan aplikasi, berita, dan tips dari Pensil Warung akan muncul di sini.',
      );
    }
    if (shown.isEmpty) return const EmptyState(icon: Icons.done_all_rounded, title: 'Semua sudah dibaca');
    return RefreshIndicator(
      onRefresh: feed.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _Row(b: shown[i], unread: feed.isUnread(shown[i]), onTap: () => _open(shown[i])),
      ),
    );
  }

  void _open(Broadcast b) {
    final feed = context.read<NotificationFeed>();
    feed.markRead(b.id);
    showAppSheet<void>(context, builder: (_) => _DetailBody(b: b, body: feed.body(b)));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 20, 12),
        child: Row(
          children: [
            IconButton(tooltip: 'Kembali', onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_back_rounded)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notifikasi', style: appText(30, weight: FontWeight.w800, letterSpacing: -0.5)),
                  Text(subtitle, style: appText(14, color: AppColors.muted)),
                ],
              ),
            ),
            const AvatarButton(),
          ],
        ),
      );
}

/// The design's yellow-pill filter (not the grey SegmentedTabs).
class _Filter extends StatelessWidget {
  const _Filter({required this.selectedUnread, required this.onChanged});

  final bool selectedUnread;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppColors.disabled, borderRadius: BorderRadius.circular(26)),
        child: Row(
          children: [
            for (final (label, unread) in [('Semua', false), ('Belum dibaca', true)])
              Expanded(
                child: Semantics(
                  button: true,
                  selected: unread == selectedUnread,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(unread),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: unread == selectedUnread ? AppColors.accent : null,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        label,
                        style: appText(14,
                            weight: unread == selectedUnread ? FontWeight.w800 : FontWeight.w600,
                            color: unread == selectedUnread ? AppColors.onAccent : AppColors.ink),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

IconData _icon(String category) => switch (category) {
      'update' => Icons.system_update_alt_rounded,
      'berita' => Icons.campaign_outlined,
      'tips' => Icons.lightbulb_outline_rounded,
      _ => Icons.info_outline_rounded,
    };

class _Row extends StatelessWidget {
  const _Row({required this.b, required this.unread, required this.onTap});

  final Broadcast b;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14)),
                child: Icon(_icon(b.category), size: 22, color: AppColors.label),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${b.categoryLabel} · ${timeAgo(b.shownAt)}',
                              style: appText(13, weight: FontWeight.w700, color: AppColors.muted)),
                        ),
                        if (unread)
                          Semantics(
                            label: 'Belum dibaca',
                            child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(b.title, style: appText(17, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(b.summary, style: appText(15, color: AppColors.label).copyWith(height: 21 / 15)),
                  ],
                ),
              ),
            ],
          ),
      );
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.b, required this.body});

  final Broadcast b;
  final Future<String?> body;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${b.categoryLabel} · ${timeAgo(b.shownAt)}', style: appText(13, weight: FontWeight.w700, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(b.title, style: appText(20, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(b.summary, style: appText(15, color: AppColors.label)),
          if (b.hasBody)
            FutureBuilder<String?>(
              future: body,
              builder: (context, snap) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: snap.connectionState != ConnectionState.done
                    ? const Center(child: CircularProgressIndicator())
                    : Text(snap.hasError ? 'Isi lengkap belum bisa dimuat. Coba lagi nanti.' : snap.data ?? '',
                        style: appText(15, color: snap.hasError ? AppColors.error : AppColors.ink).copyWith(height: 22 / 15)),
              ),
            ),
        ],
      );
}
