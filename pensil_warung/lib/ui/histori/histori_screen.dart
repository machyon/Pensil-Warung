import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/analytics.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/error_view.dart';
import '../core/widgets/month_stepper.dart';
import '../core/widgets/segmented_tabs.dart';
import 'analitik_view.dart';
import 'day_tile.dart';
import 'histori_view_model.dart';
import 'month_picker_sheet.dart';
import '../notifications/notification_feed.dart';

const _firstDays = 7;

class HistoriScreen extends StatelessWidget {
  const HistoriScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => HistoriViewModel(c.read<AnalyticsRepository>(), c.read<TransactionRepository>()),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  int _tab = 0; // 1 = Analitik

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HistoriViewModel>();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(title: _tab == 1 && vm.summary != null && AnalitikView.isFull(vm) ? 'Laporan Analitik' : 'Histori', avatar: true, hasUnread: context.select<NotificationFeed, bool>((f) => f.hasUnread), onBell: () => context.push('/notifikasi')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SegmentedTabs(labels: const ['Histori', 'Analitik'], selected: _tab, onChanged: (i) => setState(() => _tab = i)),
          ),
          Expanded(child: _content(context, vm)),
          if (!vm.isEmpty && vm.error == null && !vm.loading)
            Container(
              decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: MonthStepper(
                year: int.parse(vm.month.substring(0, 4)),
                month: int.parse(vm.month.substring(5, 7)),
                onPrev: vm.canPrev ? () => vm.step(-1) : null,
                onNext: vm.canNext ? () => vm.step(1) : null,
                onPick: () async {
                  final m = await showMonthPicker(context, selected: vm.month, first: vm.firstMonth, last: HistoriViewModel.currentMonth);
                  if (m != null) vm.setMonth(m);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, HistoriViewModel vm) {
    if (vm.error != null && vm.summary == null) return ErrorView(error: vm.error!, onRetry: vm.load);
    if (vm.loading && vm.summary == null) return const Center(child: CircularProgressIndicator());
    if (vm.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        title: 'Belum ada jualan',
        text: 'Jualan yang kamu simpan di Catat akan muncul di sini, dikelompokkan per hari.',
        actionLabel: 'Catat jualan pertama',
        onAction: () => context.go('/catat'),
        footer: Column(children: [
          Text('Coba ketik di Catat', style: appText(13, color: AppColors.muted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
            child: Text('nasi goreng 2', style: monoText(15)),
          ),
        ]),
      );
    }
    if (_tab == 1) return AnalitikView(vm: vm);
    final s = vm.summary;
    final shown = vm.showAll ? vm.days : vm.days.take(_firstDays).toList();
    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          if (s != null) _SummaryCard(vm: vm, s: s),
          if (s != null && s.topItems.isNotEmpty) ...[const SizedBox(height: 12), _TopCard(items: s.topItems.take(3).toList())],
          const SizedBox(height: 16),
          Text('Per hari', style: appText(18, weight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (vm.days.isEmpty && !vm.loading)
            Padding(padding: const EdgeInsets.all(16), child: Text('Belum ada jualan bulan ini.', style: appText(15, color: AppColors.muted))),
          for (final d in shown) ...[DayTile(vm: vm, d: d), const SizedBox(height: 8)],
          if (!vm.showAll && vm.days.length > _firstDays)
            TextButton(onPressed: vm.expandList, child: Text('Lihat semua ${vm.days.length} hari', style: appText(15, weight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.vm, required this.s});
  final HistoriViewModel vm;
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final current = vm.month == HistoriViewModel.currentMonth;
    final mon = monthNames[int.parse(vm.month.substring(5, 7)) - 1];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(current ? 'Penjualan bulan ini' : 'Penjualan $mon', style: appText(14, weight: FontWeight.w600, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(rupiah(s.revenue), style: appText(30, weight: FontWeight.w800, letterSpacing: -0.5)),
        Text('${s.count} transaksi · s.d. ${s.throughDay} ${mon.substring(0, 3)}', style: appText(14, color: AppColors.muted)),
      ]),
    );
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({required this.items});
  final List<TopItem> items;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Terlaris', style: appText(14, weight: FontWeight.w700, color: AppColors.muted)),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
                child: Text('${i + 1}', style: appText(13, weight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(items[i].name, style: appText(15, weight: FontWeight.w700))),
              Text('${items[i].qty}', style: appText(15, weight: FontWeight.w800)),
            ]),
          ),
      ]),
    );
  }
}
