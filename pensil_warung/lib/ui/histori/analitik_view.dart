import 'package:material_ui/material_ui.dart';

import '../../domain/analytics.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import 'day_tile.dart';
import 'histori_view_model.dart';

const _firstDays = 7;

/// "▲ 8% dari 1–17 Okt · 641 transaksi"; null change_pct hides the arrow part.
String comparisonLine(MonthSummary s) {
  final pct = s.previous.changePct;
  final upTo = s.throughDay.clamp(1, daysInMonth(s.previous.month));
  final part = '${s.count} transaksi';
  if (pct == null) return part;
  final arrow = pct < 0 ? '▼' : '▲';
  return '$arrow ${percent(pct.abs())}% dari 1–$upTo ${monthShort(s.previous.month)} · $part';
}

/// The Analitik segment of the Histori tab. Reads the month, summary and days from [vm].
class AnalitikView extends StatelessWidget {
  const AnalitikView({super.key, required this.vm});
  final HistoriViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.summary;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final shown = vm.showAll ? vm.days : vm.days.take(_firstDays).toList();
    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Text('Laporan Analitik', style: appText(20, weight: FontWeight.w800)),
          const SizedBox(height: 12),
          _SummaryCard(vm: vm, s: s),
          const SizedBox(height: 12),
          _TrendCard(vm: vm, s: s),
          const SizedBox(height: 16),
          Text('Per hari', style: appText(18, weight: FontWeight.w800)),
          const SizedBox(height: 8),
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
    final mon = monthNames[int.parse(s.month.substring(5, 7)) - 1];
    final pct = s.previous.changePct;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.month == HistoriViewModel.currentMonth ? 'Penjualan bulan ini' : 'Penjualan $mon',
            style: appText(14, weight: FontWeight.w600, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(rupiah(s.revenue), style: appText(30, weight: FontWeight.w800, letterSpacing: -0.5)),
        Text(comparisonLine(s),
            style: appText(14, weight: FontWeight.w600, color: pct == null ? AppColors.muted : pct < 0 ? AppColors.error : AppColors.label)),
      ]),
    );
  }
}

/// 12 bars, the viewed month in accent; a tap switches the month (not before the first sale).
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.vm, required this.s});
  final HistoriViewModel vm;
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final max = s.trend.fold<int>(0, (m, t) => t.revenue > m ? t.revenue : m);
    final first = monthIndex(vm.firstMonth);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 8), child: Text('Penjualan 12 bulan', style: appText(14, weight: FontWeight.w700, color: AppColors.muted))),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final t in s.trend)
              Expanded(
                child: Semantics(
                  button: true,
                  label: '${monthNames[int.parse(t.month.substring(5, 7)) - 1]}, ${rupiah(t.revenue)}',
                  child: InkWell(
                    onTap: monthIndex(t.month) < first ? null : () => vm.setMonth(t.month),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      SizedBox(
                        height: 14,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(t.revenue == 0 ? '' : rupiahCompact(t.revenue), style: appText(10, weight: FontWeight.w700, color: AppColors.label)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: max == 0 ? 3 : 3 + 100.0 * t.revenue / max,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: t.month == s.month ? AppColors.accent : AppColors.chip,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(monthShort(t.month),
                          style: appText(10, weight: t.month == s.month ? FontWeight.w800 : FontWeight.w600,
                              color: t.month == s.month ? AppColors.ink : AppColors.muted)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
