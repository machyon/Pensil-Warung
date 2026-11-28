import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/error_view.dart';
import '../core/widgets/product_avatar.dart';
import 'barang_view_model.dart';

const _segmentColors = [AppColors.accent, AppColors.avatar, AppColors.faint, AppColors.fieldBorder, Color(0xFFB98A00), AppColors.chip];

/// [09] "Semua barang terjual" for [month] (`YYYY-MM`).
class BarangScreen extends StatelessWidget {
  const BarangScreen({super.key, required this.month});
  final String month;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => BarangViewModel(c.read<AnalyticsRepository>(), month),
        child: _Body(month: month),
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.month});
  final String month;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BarangViewModel>();
    final d = vm.data;
    final products = context.watch<ProductRepository>().items;
    String? photo(int? id) => id == null ? null : products.where((p) => p.id == id).firstOrNull?.photoUrl;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          BackHeader(title: 'Barang terjual ${monthNames[int.parse(month.substring(5, 7)) - 1]}'),
          Expanded(
            child: d == null
                ? vm.error != null
                    ? ErrorView(error: vm.error!, onRetry: vm.load)
                    : const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: _stat('Terjual', '${d.totalQty}')),
                            Expanded(child: _stat('Pendapatan', rupiah(d.revenue))),
                          ]),
                          if (vm.segments.isNotEmpty) ...[const SizedBox(height: 14), _ShareBar(segments: vm.segments)],
                        ]),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        onChanged: vm.search,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Cari barang',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.fieldBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.fieldBorder)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (d.items.isEmpty && d.unsold.isEmpty)
                        Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Tidak ada barang yang cocok.', style: appText(15, color: AppColors.muted)))),
                      for (final i in d.items) _row(i.item.name, photo(i.item.productId), '${percent(i.sharePct)}% · ${rupiah(i.item.revenue)}', '${i.item.qty} terjual', i.item.stock),
                      if (d.unsold.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Belum terjual bulan ini', style: appText(16, weight: FontWeight.w800)),
                        for (final u in d.unsold) _row(u.name, photo(u.id), null, null, u.stock),
                      ],
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
        Text(value, style: appText(22, weight: FontWeight.w800)),
      ]);

  Widget _row(String name, String? photoUrl, String? top, String? sub, int? stock) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          ProductAvatar(name: name, photoUrl: photoUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: appText(15, weight: FontWeight.w700)),
              if (top != null) Text(top, style: appText(13, color: AppColors.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (sub != null) Text(sub, style: appText(14, weight: FontWeight.w700)),
            if (stock != null) Text('Stok $stock', style: appText(13, color: AppColors.muted)),
          ]),
        ]),
      );
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.segments});
  final List<({String label, double pct})> segments;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 12,
          child: Row(children: [
            for (var i = 0; i < segments.length; i++)
              Expanded(flex: (segments[i].pct * 10).round().clamp(1, 1000), child: Container(color: _segmentColors[i % _segmentColors.length])),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 4, children: [
        for (var i = 0; i < segments.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _segmentColors[i % _segmentColors.length], shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('${segments[i].label} ${percent(segments[i].pct)}%', style: appText(12, weight: FontWeight.w600, color: AppColors.label)),
          ]),
      ]),
    ]);
  }
}
