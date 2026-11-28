import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/analytics.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/day_card.dart';
import '../core/widgets/error_view.dart';
import 'histori_view_model.dart';

/// A "Per hari" card (Histori and Analitik): expands to the day's top 3.
class DayTile extends StatelessWidget {
  const DayTile({super.key, required this.vm, required this.d});
  final HistoriViewModel vm;
  final DayTotal d;

  @override
  Widget build(BuildContext context) {
    final items = vm.dayItems[d.day];
    return DayCard(
      title: d.day == HistoriViewModel.today ? 'Hari ini' : dayShort(d.day),
      subtitle: '${d.count} transaksi',
      trailing: rupiah(d.revenue),
      expanded: vm.expanded == d.day,
      onToggle: () => vm.toggle(d.day),
      children: [
        if (vm.expanded == d.day && items == null && vm.dayError != null)
          ErrorView(error: vm.dayError!, onRetry: vm.retryItems)
        else if (items == null)
          const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
        else ...[
          Align(alignment: Alignment.centerLeft, child: Text('Barang terjual', style: appText(13, weight: FontWeight.w700, color: AppColors.muted))),
          for (final i in items.items) _row(i.name, '${i.qty} terjual', rupiah(i.revenue)),
          if (items.other > 0) _row('Barang lain', null, rupiah(items.other)),
          const Divider(height: 24),
          Row(children: [
            Expanded(child: Text('Total', style: appText(15, weight: FontWeight.w800))),
            Text(rupiah(items.total), style: appText(16, weight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.push('/hari/${d.day}'),
            child: Text('Lihat ${d.count} transaksi', style: appText(15, weight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _row(String name, String? sub, String amount) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: appText(15, weight: FontWeight.w700)),
              if (sub != null) Text(sub, style: appText(13, color: AppColors.muted)),
            ]),
          ),
          Text(amount, style: appText(15, weight: FontWeight.w700)),
        ]),
      );
}
