import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../domain/analytics.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/product_avatar.dart';
import 'day_tile.dart';
import 'histori_view_model.dart';

const _firstDays = 7;
const fullReportDays = 14; // weekday chart
const topItemsDays = 7;

/// Which sections have enough data, from the days with sales ([days]) and the API's own nulls.
({bool weekday, bool top, bool comparison}) analitikGates(MonthSummary s, int days) => (
      weekday: days >= fullReportDays && s.weekdayAvg != null,
      top: days >= topItemsDays && s.topItems.isNotEmpty,
      comparison: s.previous.changePct != null,
    );


/// "▲ 8% dari 1–17 Okt · 641 transaksi"; null change_pct hides the arrow part.
String comparisonLine(MonthSummary s) {
  final pct = s.previous.changePct;
  final upTo = s.throughDay.clamp(1, daysInMonth(s.previous.month));
  final part = '${s.count} transaksi';
  if (pct == null) return part;
  final arrow = pct < 0 ? '▼' : '▲';
  return '$arrow ${percent(pct.abs())}% dari 1–$upTo ${monthShort(s.previous.month)} · $part';
}

/// Hari paling ramai: the best and the quietest weekday of [avg] (Monday first, 7 values).
({
  String best,
  String worst,
  int mean,
  int bestIndex,
  int worstIndex,
  int worstValue,
})
weekdayStats(List<int> avg) {
  var b = 0, w = 0;
  for (var i = 1; i < avg.length; i++) {
    if (avg[i] > avg[b]) b = i;
    if (avg[i] < avg[w]) w = i;
  }
  return (
    best: dayNames[b],
    worst: dayNames[w],
    mean: avg.reduce((a, c) => a + c) ~/ avg.length,
    bestIndex: b,
    worstIndex: w,
    worstValue: avg[w],
  );
}

/// "Top-revenue menyumbang P% penjualan, walau top-qty paling banyak terjual.", or "Name paling laris bulan ini." when they are the same item.
String topItemsSentence(List<TopItem> top, int monthRevenue) {
  var byRev = top.first;
  for (final i in top) {
    if (i.revenue > byRev.revenue) byRev = i;
  }
  final byQty = top.first; // the API ranks by quantity first
  if (identical(byRev, byQty) || monthRevenue == 0) {
    return '${byQty.name} paling laris bulan ini.';
  }
  return '${byRev.name} menyumbang ${(byRev.revenue * 100 / monthRevenue).round()}% penjualan, walau ${byQty.name} paling banyak terjual.';
}

/// The Analitik segment of the Histori tab. Reads the month, summary and days from [vm].
class AnalitikView extends StatelessWidget {
  const AnalitikView({super.key, required this.vm});
  final HistoriViewModel vm;

  /// Under 14 days with sales the "belum cukup data" layout ([34]) shows instead of the full report.
  static bool isFull(HistoriViewModel vm) => vm.days.length >= fullReportDays;

  @override
  Widget build(BuildContext context) {
    final s = vm.summary;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final g = analitikGates(s, vm.days.length);
    final full = isFull(vm);
    final shown = vm.showAll ? vm.days : vm.days.take(_firstDays).toList();
    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (full) _HeroCard(vm: vm, s: s) else _PlainSummary(s: s, days: vm.days.length),
          if (!full) ...[const SizedBox(height: 12), _ProgressCard(days: vm.days.length)],
          if (g.weekday) ...[_h2('Hari paling ramai'), _WeekdayCard(s: s, avg: s.weekdayAvg!)],
          if (g.top) ...[_h2('Barang terlaris'), _TopItemsCard(s: s)],
          if (!g.weekday || !g.top || !g.comparison) ...[
            const SizedBox(height: 16),
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('Akan muncul nanti', style: appText(13, weight: FontWeight.w600, color: AppColors.muted))),
            _LaterList(s: s, g: g),
          ],
          if (full) ...[
            _h2('Per hari'),
            for (final d in shown) ...[DayTile(vm: vm, d: d), const SizedBox(height: 8)],
            if (!vm.showAll && vm.days.length > _firstDays)
              TextButton(onPressed: vm.expandList, child: Text('Lihat semua ${vm.days.length} hari', style: appText(15, weight: FontWeight.w700))),
          ],
        ],
      ),
    );
  }
}

Widget _h2(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 24, 4, 12), child: Text(t, style: appText(17, weight: FontWeight.w800)));

BoxDecoration _card([double radius = 24]) => BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(radius), border: Border.all(color: AppColors.border));

/// Yellow summary with the 12-month trend inside; a tap on a bar switches the month (not before the first sale).
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.vm, required this.s});
  final HistoriViewModel vm;
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final max = s.trend.fold<int>(0, (m, t) => t.revenue > m ? t.revenue : m);
    final first = monthIndex(vm.firstMonth);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(28)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(monthYear(int.parse(s.month.substring(0, 4)), int.parse(s.month.substring(5, 7))), style: appText(14, weight: FontWeight.w700, color: AppColors.onAccent)),
        Text(rupiah(s.revenue), style: appText(40, weight: FontWeight.w800, letterSpacing: -1, color: AppColors.onAccent)),
        Text(comparisonLine(s), style: appText(14, weight: FontWeight.w600, color: AppColors.onAccent)),
        const SizedBox(height: 14),
        SizedBox(
          height: 84,
          child: Row(children: [
            for (final t in s.trend)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: t.month == s.month,
                  label: '${monthNames[int.parse(t.month.substring(5, 7)) - 1]}, ${rupiah(t.revenue)}',
                  child: InkWell(
                    onTap: monthIndex(t.month) < first ? null : () => vm.setMonth(t.month),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      SizedBox(
                        height: 14,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(t.revenue == 0 ? '' : rupiahCompact(t.revenue), style: appText(11, weight: t.month == s.month ? FontWeight.w800 : FontWeight.w600, color: AppColors.onAccent)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: max == 0 ? 3 : 3 + 37.0 * t.revenue / max,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: t.month == s.month ? AppColors.onAccent : const Color(0xFFAA8417),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        alignment: Alignment.center,
                        decoration: t.month == s.month ? BoxDecoration(color: AppColors.onAccent, borderRadius: BorderRadius.circular(6)) : null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(monthShort(t.month), style: appText(12, weight: t.month == s.month ? FontWeight.w800 : FontWeight.w600, color: t.month == s.month ? AppColors.accent : AppColors.onAccent)),
                        ),
                      ),
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

/// [34] white summary: "N transaksi · N hari tercatat".
class _PlainSummary extends StatelessWidget {
  const _PlainSummary({required this.s, required this.days});
  final MonthSummary s;
  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(monthYear(int.parse(s.month.substring(0, 4)), int.parse(s.month.substring(5, 7))), style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
        const SizedBox(height: 2),
        Text(rupiah(s.revenue), style: appText(30, weight: FontWeight.w800, letterSpacing: -0.6)),
        const SizedBox(height: 2),
        Text('${s.count} transaksi · $days hari tercatat', style: appText(13, color: AppColors.muted)),
      ]),
    );
  }
}

class _WeekdayCard extends StatelessWidget {
  const _WeekdayCard({required this.s, required this.avg});
  final MonthSummary s;
  final List<int> avg;

  @override
  Widget build(BuildContext context) {
    final st = weekdayStats(avg);
    final max = avg[st.bestIndex];
    final mon = monthNames[int.parse(s.month.substring(5, 7)) - 1];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${st.best} biasanya paling laris', style: appText(16, weight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Rata-rata ${rupiah(st.mean)}. Paling sepi hari ${st.worst}, ${rupiah(st.worstValue)}.', style: appText(14, color: AppColors.label).copyWith(height: 20 / 14)),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  FittedBox(fit: BoxFit.scaleDown, child: Text(rupiahCompact(avg[i]), style: appText(12, weight: i == st.bestIndex ? FontWeight.w800 : FontWeight.w600, color: i == st.bestIndex ? AppColors.ink : AppColors.muted))),
                  const SizedBox(height: 4),
                  Container(
                    height: max == 0 ? 3 : 3 + 69.0 * avg[i] / max,
                    decoration: BoxDecoration(
                      color: i == st.bestIndex ? AppColors.accent : AppColors.fieldBorder,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8), bottom: Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(dayNames[i].substring(0, 3), style: appText(13, weight: i == st.bestIndex ? FontWeight.w800 : FontWeight.w600)),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Text('Rata-rata dari ${s.throughDay} hari di $mon. Hari dihitung dalam WIB.', style: appText(13, color: AppColors.muted)),
      ]),
    );
  }
}

class _StokPill extends StatelessWidget {
  const _StokPill(this.stock);
  final int stock;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
        child: Text('Stok $stock', style: appText(13, weight: FontWeight.w700, color: AppColors.label)),
      );
}

class _TopItemsCard extends StatelessWidget {
  const _TopItemsCard({required this.s});
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductRepository>().items;
    final top = s.topItems.take(3).toList();
    return Container(
      decoration: _card(),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.label)),
            const SizedBox(width: 8),
            Expanded(child: Text(topItemsSentence(s.topItems, s.revenue), style: appText(14, color: AppColors.label).copyWith(height: 20 / 14))),
          ]),
        ),
        for (final i in top)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              ProductAvatar(name: i.name, size: 44, photoUrl: i.productId == null ? null : products.where((p) => p.id == i.productId).firstOrNull?.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.name, style: appText(15, weight: FontWeight.w700)),
                  Text('${i.qty} terjual · ${rupiah(i.revenue)}', style: appText(13, color: AppColors.muted)),
                ]),
              ),
              if (i.stock != null) _StokPill(i.stock!),
            ]),
          ),
        InkWell(
          onTap: () => context.push('/barang/${s.month}'),
          child: Container(
            height: 48,
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              Expanded(child: Text('Lihat semua barang', style: appText(15, weight: FontWeight.w700))),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// [34] "Laporan lengkap sedang disiapkan".
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.bar_chart_rounded, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Laporan lengkap sedang disiapkan', style: appText(17, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Butuh $fullReportDays hari jualan supaya polanya akurat', style: appText(13, color: AppColors.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: (days / fullReportDays).clamp(0, 1), minHeight: 10, backgroundColor: AppColors.chip, color: AppColors.accent),
        ),
        const SizedBox(height: 6),
        Text('$days dari $fullReportDays hari · ${fullReportDays - days} hari lagi', style: appText(13, weight: FontWeight.w700)),
      ]),
    );
  }
}

/// "Akan muncul nanti": the sections whose gate has not passed.
class _LaterList extends StatelessWidget {
  const _LaterList({required this.s, required this.g});
  final MonthSummary s;
  final ({bool weekday, bool top, bool comparison}) g;

  @override
  Widget build(BuildContext context) {
    final next = monthNames[int.parse(s.month.substring(5, 7)) % 12];
    final rows = <(Widget, String, String)>[
      if (!g.weekday) (const _MiniBars(), 'Hari paling ramai', 'Setelah $fullReportDays hari'),
      if (!g.comparison) (const Icon(Icons.trending_up_rounded, size: 24, color: AppColors.faint), 'Dibanding bulan lalu', 'Mulai $next'),
      if (!g.top) (const Icon(Icons.star_outline_rounded, size: 24, color: AppColors.faint), 'Barang terlaris', 'Setelah $topItemsDays hari'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: _card(),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
            child: Row(children: [
              SizedBox(width: 44, height: 32, child: Center(child: rows[i].$1)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rows[i].$2, style: appText(15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(rows[i].$3, style: appText(13, color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 32,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final h in const [0.4, 0.7, 0.55, 1.0]) ...[
            Expanded(child: FractionallySizedBox(heightFactor: h, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.disabled, borderRadius: BorderRadius.circular(3))))),
            if (h != 1.0) const SizedBox(width: 3),
          ],
        ]),
      );
}
