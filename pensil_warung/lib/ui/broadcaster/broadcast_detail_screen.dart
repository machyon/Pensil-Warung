import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/broadcaster_repository.dart';
import '../../domain/broadcast.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/category_icon.dart';
import '../core/widgets/error_view.dart';
import 'broadcast_detail_view_model.dart';
import 'broadcast_draft.dart';
import 'broadcast_widgets.dart';
import 'siaran_view_model.dart';

/// [21] Terjadwal (also Dibatalkan) and [22] Terkirim: one page, chosen by `effective_status`.
class BroadcastDetailScreen extends StatelessWidget {
  const BroadcastDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => BroadcastDetailViewModel(c.read<BroadcasterRepository>(), c.read<SiaranViewModel>(), id)..load(),
        child: const _Page(),
      );
}

class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BroadcastDetailViewModel>();
    final b = vm.item;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SiaranHeader(
            title: 'Detail siaran',
            subtitle: b == null
                ? ' '
                : '${b.status == 'sent' ? 'Dikirim' : 'Dibuat'} oleh ${b.createdByName ?? 'penyiar'} · ${wibRelative(b.status == 'sent' ? b.shownAt : _created(b))}',
            onBack: () => context.pop(),
          ),
          Expanded(
            child: b == null
                ? (vm.error != null ? ErrorView(error: vm.error!, onRetry: vm.load) : const Center(child: CircularProgressIndicator()))
                : _Body(b: b, notEditable: vm.error),
          ),
          if (b != null) _Actions(b: b, vm: vm),
        ]),
      ),
    );
  }

  DateTime _created(Broadcast b) => b.createdAt ?? b.shownAt;
}

class _Body extends StatelessWidget {
  const _Body({required this.b, this.notEditable});

  final Broadcast b;
  final Object? notEditable;

  @override
  Widget build(BuildContext context) {
    final count = context.select<SiaranViewModel, int>((v) => v.recipientCount);
    final scheduled = b.status == 'scheduled', cancelled = b.status == 'cancelled';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
      if (notEditable != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(16)),
          child: Text(messageOf(notEditable!), style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
        ),
        const SizedBox(height: 12),
      ],
      AppCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Pill(
            icon: scheduled ? Icons.schedule_rounded : cancelled ? Icons.cancel_outlined : Icons.check_rounded,
            label: scheduled ? 'Terjadwal' : cancelled ? 'Dibatalkan' : 'Terkirim',
            fg: scheduled ? AppColors.onAccent : cancelled ? AppColors.error : AppColors.ink,
            bg: scheduled ? AppColors.accent : cancelled ? AppColors.errorBg : AppColors.chip,
          ),
          const SizedBox(height: 12),
          Text(cancelled ? 'Tidak akan dikirim' : '${wibRelative(b.shownAt)} WIB',
              style: appText(26, weight: FontWeight.w800, letterSpacing: -0.4).copyWith(height: 32 / 26)),
          const SizedBox(height: 4),
          Text(
            scheduled
                ? 'Terkirim ${untilText(b.shownAt, long: true)}'
                : cancelled
                    ? 'Dibatalkan oleh ${b.cancelledByName ?? 'penyiar'}, ${b.cancelledAt == null ? '' : wibRelative(b.cancelledAt!).toLowerCase()}'
                    : 'Sudah dikirim ke semua pengguna',
            style: appText(15, weight: FontWeight.w600, color: AppColors.label),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.groups_outlined, size: 20, color: AppColors.label),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Semua pengguna', style: appText(15, weight: FontWeight.w700)),
                Text('${groupedDigits(count)} akun', style: appText(14, color: AppColors.label)),
              ]),
            ),
          ]),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: _Muted('Pesan'),
      ),
      AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CategoryBadge(b.category),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
              child: Text(b.categoryLabel, style: appText(13, weight: FontWeight.w700, color: AppColors.label)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(b.title, style: appText(20, weight: FontWeight.w800, letterSpacing: -0.3).copyWith(height: 26 / 20)),
          const SizedBox(height: 12),
          Text(b.summary, style: appText(15, weight: FontWeight.w600).copyWith(height: 22 / 15)),
          if ((b.body ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(b.body!, style: appText(15, color: AppColors.label).copyWith(height: 22 / 15)),
          ],
        ]),
      ),
      if (b.status == 'sent')
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Siaran yang sudah terkirim tidak bisa diubah atau ditarik. Untuk meralat, kirim siaran baru.',
                  style: appText(13, weight: FontWeight.w600, color: AppColors.muted).copyWith(height: 18 / 13)),
            ),
          ]),
        ),
    ]);
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: appText(13, weight: FontWeight.w600, color: AppColors.muted));
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.fg, required this.bg});

  final IconData icon;
  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(label, style: appText(14, weight: FontWeight.w800, color: fg)),
        ]),
      );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.b, required this.vm});

  final Broadcast b;
  final BroadcastDetailViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheduled = b.status == 'scheduled';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(children: [
        if (scheduled) ...[
          SizedBox(
            width: 136,
            child: Semantics(
              button: true,
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.error)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: vm.running ? null : () => _cancel(context),
                  child: SizedBox(
                    height: 56,
                    child: Center(child: Text('Batalkan', style: appText(17, weight: FontWeight.w700, color: AppColors.error))),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: PrimaryButton(label: 'Ubah', onPressed: () => _edit(context))),
        ] else
          Expanded(child: PrimaryButton(label: 'Buat siaran baru', onPressed: () => _new(context))),
      ]),
    );
  }

  void _new(BuildContext context) {
    context.read<BroadcastDraft>().reset();
    context.go('/tulis');
  }

  void _edit(BuildContext context) {
    context.read<BroadcastDraft>().startEdit(b);
    context.go('/tulis');
  }

  Future<void> _cancel(BuildContext context) async {
    final count = context.read<SiaranViewModel>().recipientCount;
    final ok = await showAppSheet<bool>(
      context,
      builder: (context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Batalkan siaran ini?', style: appText(22, weight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 12),
        Text('Siaran tidak akan dikirim ke ${groupedDigits(count)} pengguna. Kalau ingin mengirimnya nanti, kamu perlu membuatnya lagi.',
            style: appText(15, color: AppColors.label).copyWith(height: 22 / 15)),
        const SizedBox(height: 18),
        Row(children: [
          SizedBox(width: 120, child: SecondaryButton(label: 'Kembali', onPressed: () => Navigator.pop(context, false))),
          const SizedBox(width: 12),
          Expanded(child: DangerButton(label: 'Ya, batalkan', onPressed: () => Navigator.pop(context, true))),
        ]),
      ]),
    );
    if (ok != true || !context.mounted) return;
    if (await vm.cancel() && context.mounted) context.pop(); // gone from Terjadwal
  }
}
