import 'package:material_ui/material_ui.dart';

import '../../catat/summary.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';

/// [12] CatatKonfirmasi. True for "Simpan semua".
Future<bool> showConfirmSheet(BuildContext context, ConfirmSummary s, {required int lineCount}) async {
  final ok = await showAppSheet<bool>(context, builder: (context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Simpan catatan ini?', style: appText(22, weight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 4),
          Text('$lineCount baris · ${wibDateShort(DateTime.now())}', style: appText(14, color: AppColors.muted)),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (s.sales.isNotEmpty)
                  _Section('Jualan', '${s.items} barang, ${s.portions} porsi', right: rupiah(s.total)),
                for (final n in s.newProducts)
                  _Section('Barang baru', '${n.name}, ${rupiah(n.price)}, stok ${n.stock}'),
                for (final c in s.priceChanges)
                  _Section('Ubah harga', '${c.name}, ${rupiah(c.oldPrice)} jadi ${rupiah(c.newPrice)}'),
                for (final r in s.restocks)
                  _Section('Stok masuk', r.name, right: '+${r.quantity}'),
                for (final o in s.stockOuts)
                  _Section('Stok keluar', '${o.name}${o.reason == null ? '' : ', ${o.reason}'}. ${o.note ?? notInTotal}',
                      right: '−${o.quantity}'),
                for (final d in s.deletions)
                  _Section('Hapus barang', '${d.name}, sisa stok ${d.remainingStock}', warning: d.warning),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SecondaryButton(label: 'Periksa lagi', onPressed: () => Navigator.pop(context, false)),
          const SizedBox(height: 10),
          PrimaryButton(label: 'Simpan semua', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
  });
  return ok ?? false;
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.text, {this.right, this.warning});

  final String title, text;
  final String? right, warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.toUpperCase(), style: appText(12, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
              Text(text, style: appText(16, weight: FontWeight.w700)),
              if (warning != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(warning!, style: appText(13, weight: FontWeight.w600, color: AppColors.error)),
                ),
            ]),
          ),
          if (right != null) Text(right!, style: appText(16, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}
