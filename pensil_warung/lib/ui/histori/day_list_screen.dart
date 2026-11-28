import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/error_view.dart';
import 'date_picker_sheet.dart';
import 'histori_view_model.dart';
import 'day_list_view_model.dart';

/// One day's transactions (not in the design): opened from a day card and from PilihTanggal.
class DayListScreen extends StatelessWidget {
  const DayListScreen({super.key, required this.date});

  final String date;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        key: ValueKey(date),
        create: (c) => DayListViewModel(c.read<TransactionRepository>(), date),
        child: _Body(date: date),
      );
}

class _Body extends StatefulWidget {
  const _Body({required this.date});
  final String date;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) context.read<DayListViewModel>().loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showDatePickerSheet(context, context.read<AnalyticsRepository>(), widget.date);
    if (picked != null && picked != widget.date && mounted) context.pushReplacement('/hari/$picked');
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DayListViewModel>();
    final d = vm.day;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BackHeader(
              title: dayLong(widget.date),
              trailing: IconButton(tooltip: 'Pilih tanggal', onPressed: _pick, icon: const Icon(Icons.calendar_month_outlined)),
            ),
            Expanded(
              child: vm.error != null && vm.rows.isEmpty
                  ? ErrorView(error: vm.error!, onRetry: vm.load)
                  : vm.loading && vm.rows.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: vm.load,
                          child: ListView(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              if (d != null)
                                AppCard(
                                  child: Row(children: [
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(widget.date == HistoriViewModel.today ? 'Jualan hari ini' : 'Jualan hari itu', style: appText(14, weight: FontWeight.w600, color: AppColors.muted)),
                                        Text(rupiah(d.revenue), style: appText(26, weight: FontWeight.w800)),
                                      ]),
                                    ),
                                    Text('${d.count} transaksi', style: appText(15, weight: FontWeight.w700, color: AppColors.label)),
                                  ]),
                                ),
                              const SizedBox(height: 12),
                              if (vm.rows.isEmpty)
                                const SizedBox(height: 320, child: EmptyState(icon: Icons.receipt_long_outlined, title: 'Tidak ada transaksi'))
                              else
                                AppCard(
                                  padding: EdgeInsets.zero,
                                  child: Column(children: [
                                    for (var i = 0; i < vm.rows.length; i++) ...[
                                      if (i > 0) const Divider(height: 1),
                                      _Row(row: vm.rows[i]),
                                    ],
                                  ]),
                                ),
                              if (vm.loadingMore)
                                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});
  final TxRow row;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/transaksi/${row.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(width: 44, child: Text(wibTime(row.occurredAt), style: appText(14, weight: FontWeight.w700, color: AppColors.muted))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, weight: FontWeight.w600)),
              if (row.voided)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(8)),
                  child: Text('Dibatalkan', style: appText(12, weight: FontWeight.w700, color: AppColors.error)),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Text(
            rupiah(row.total),
            style: appText(15, weight: FontWeight.w800, color: row.voided ? AppColors.faint : AppColors.ink)
                .copyWith(decoration: row.voided ? TextDecoration.lineThrough : null),
          ),
        ]),
      ),
    );
  }
}
