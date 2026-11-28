import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/error_view.dart';
import '../core/widgets/product_avatar.dart';
import 'barang_view_model.dart';
import 'histori_view_model.dart';

const _segmentColors = [Color(0xFFFF3B30), Color(0xFFFFCC00), Color(0xFF007AFF), Color(0xFFFF9500), Color(0xFFAF52DE), Color(0xFFC7C7CC)];

/// 4.0 -> `4,0`: the legend always shows one decimal.
String _pct1(double p) => p.toStringAsFixed(1).replaceFirst('.', ',');

/// [09] "Barang terjual" for [month] (`YYYY-MM`).
class BarangScreen extends StatelessWidget {
  const BarangScreen({super.key, required this.month});
  final String month;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => BarangViewModel(c.read<AnalyticsRepository>(), month),
        child: _Body(month: month),
      );
}

BoxDecoration _card() => BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border));

class _Body extends StatelessWidget {
  const _Body({required this.month});
  final String month;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BarangViewModel>();
    final d = vm.data;
    final products = context.watch<ProductRepository>().items;
    String? photo(int? id) => id == null ? null : products.where((p) => p.id == id).firstOrNull?.photoUrl;
    final mon = monthNames[int.parse(month.substring(5, 7)) - 1];
    final upTo = month == HistoriViewModel.currentMonth ? int.parse(HistoriViewModel.today.substring(8)) : daysInMonth(month);
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const BackHeader(title: ''),
          Expanded(
            child: d == null
                ? vm.error != null
                    ? ErrorView(error: vm.error!, onRetry: vm.load)
                    : const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Barang terjual', style: appText(30, weight: FontWeight.w800, letterSpacing: -0.5)),
                          Text('${monthYear(int.parse(month.substring(0, 4)), int.parse(month.substring(5, 7)))} · 1–$upTo ${mon.substring(0, 3)}', style: appText(14, color: AppColors.muted)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _card(),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Terjual', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
                          Text(groupedDigits(d.totalQty), style: appText(26, weight: FontWeight.w800, letterSpacing: -0.5)),
                          Text('Pendapatan ${rupiah(d.revenue)}', style: appText(13, color: AppColors.muted)),
                          if (vm.segments.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Row(children: [
                              Semantics(
                                label: 'Diagram lingkaran bagian barang terjual: ${vm.segments.map((s) => '${s.label} ${_pct1(s.pct)}%').join(', ')}',
                                child: CustomPaint(size: const Size.square(132), painter: _PiePainter([for (final s in vm.segments) s.pct])),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(children: [
                                  for (var i = 0; i < vm.segments.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                                      child: Row(children: [
                                        Container(width: 12, height: 12, decoration: BoxDecoration(color: _segmentColors[i], borderRadius: BorderRadius.circular(4))),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(vm.segments[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(14, weight: FontWeight.w600))),
                                        Text('${_pct1(vm.segments[i].pct)}%', style: appText(14, weight: FontWeight.w800)),
                                      ]),
                                    ),
                                ]),
                              ),
                            ]),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
                        child: Row(children: [
                          const Icon(Icons.search_rounded, color: AppColors.label),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              onChanged: vm.search,
                              textInputAction: TextInputAction.search,
                              style: appText(16),
                              decoration: InputDecoration(border: InputBorder.none, isCollapsed: true, hintText: 'Cari barang', hintStyle: appText(16, color: AppColors.faint)),
                            ),
                          ),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
                        child: Text('${d.items.length} barang terjual · % dari ${groupedDigits(d.totalQty)} terjual', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
                      ),
                      if (d.items.isEmpty && d.unsold.isEmpty)
                        Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Tidak ada barang yang cocok.', style: appText(15, color: AppColors.muted)))),
                      if (d.items.isNotEmpty)
                        _list([for (final i in d.items) _row(i.item.name, photo(i.item.productId), '${_pct1(i.sharePct)}% · ${rupiah(i.item.revenue)}', '${i.item.qty} terjual', i.item.stock)]),
                      if (d.unsold.isNotEmpty) ...[
                        Padding(padding: const EdgeInsets.fromLTRB(8, 24, 8, 12), child: Text('Belum terjual bulan ini', style: appText(17, weight: FontWeight.w800))),
                        _list([for (final u in d.unsold) _row(u.name, photo(u.id), '0,0% · Rp0', '0 terjual', u.stock)]),
                      ],
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _list(List<Widget> rows) => Container(
        decoration: _card(),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++)
            Container(decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))), child: rows[i]),
        ]),
      );

  Widget _row(String name, String? photoUrl, String sub, String qty, int? stock) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          ProductAvatar(name: name, photoUrl: photoUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: appText(15, weight: FontWeight.w700)),
              Text(sub, style: appText(13, color: AppColors.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(qty, style: appText(16, weight: FontWeight.w800)),
            if (stock != null) Text('Stok $stock', style: appText(12, weight: FontWeight.w600, color: AppColors.muted)),
          ]),
        ]),
      );
}

/// Pie of [pcts] (summing to about 100) from 12 o'clock, a thin white gap between slices.
class _PiePainter extends CustomPainter {
  _PiePainter(this.pcts);
  final List<double> pcts;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final total = pcts.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < pcts.length; i++) {
      final sweep = 2 * math.pi * pcts[i] / total;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = _segmentColors[i]);
      canvas.drawArc(rect, start, sweep, true, Paint()..color = AppColors.surface..style = PaintingStyle.stroke..strokeWidth = 2..strokeJoin = StrokeJoin.round);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.pcts != pcts;
}
