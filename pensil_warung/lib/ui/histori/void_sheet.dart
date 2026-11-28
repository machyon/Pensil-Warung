import 'package:material_ui/material_ui.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';

enum VoidResult { voided, alreadyVoided }

/// Day revenue after voiding [tx]'s total.
int revenueAfterVoid(int dayRevenue, int total) => dayRevenue - total;

/// [17] `TransaksiBatal`. Pops `VoidResult.voided` once the sale is voided.
Future<VoidResult?> showVoidSheet(BuildContext context, TransactionRepository repo, Transaction tx) =>
    showAppSheet<VoidResult>(context, builder: (_) => _VoidSheet(repo: repo, tx: tx));

class _VoidSheet extends StatefulWidget {
  const _VoidSheet({required this.repo, required this.tx});
  final TransactionRepository repo;
  final Transaction tx;

  @override
  State<_VoidSheet> createState() => _VoidSheetState();
}

class _VoidSheetState extends State<_VoidSheet> {
  int? _dayRevenue;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.repo.day(wibIsoDate(widget.tx.occurredAt), limit: 1).then((p) {
      if (mounted) setState(() => _dayRevenue = p.day?.revenue);
    }, onError: (_) {}); // the before/after line is a nicety
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.voidTransaction(widget.tx.id);
      if (mounted) Navigator.pop(context, VoidResult.voided);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'already_voided') return Navigator.pop(context, VoidResult.alreadyVoided);
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on NetworkException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = messageOf(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final back = tx.items.where((i) => i.productId != null).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Batalkan transaksi ini?', style: appText(22, weight: FontWeight.w800, letterSpacing: -0.4)),
        Text('${rupiah(tx.total)} · ${tx.items.length} barang · ${wibTime(tx.occurredAt)}', style: appText(14, color: AppColors.muted)),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            if (_dayRevenue != null)
              _line(
                'Jualan hari ini',
                before: rupiah(_dayRevenue!),
                after: rupiah(revenueAfterVoid(_dayRevenue!, tx.total)),
                first: true,
              ),
            for (final (i, it) in back.indexed)
              _line('Stok ${it.name} kembali', after: '+${it.quantity}', first: i == 0 && _dayRevenue == null),
          ]),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Tetap terlihat di Histori dengan tanda '),
            TextSpan(text: 'Dibatalkan', style: appText(13, weight: FontWeight.w800)),
            const TextSpan(text: ', tapi tidak dihitung lagi.'),
          ]),
          style: appText(13, color: AppColors.label),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: appText(14, weight: FontWeight.w600, color: AppColors.error)),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(flex: 10, child: SecondaryButton(label: 'Kembali', onPressed: _busy ? null : () => Navigator.pop(context))),
          const SizedBox(width: 12),
          Expanded(flex: 13, child: DangerButton(label: 'Ya, batalkan', onPressed: _confirm, busy: _busy)),
        ]),
      ],
    );
  }

  Widget _line(String label, {String? before, required String after, bool first = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Expanded(child: Text(label, style: appText(14, weight: FontWeight.w700))),
          if (before != null) ...[
            Text(before, style: appText(14, weight: FontWeight.w600, color: AppColors.muted).copyWith(decoration: TextDecoration.lineThrough)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 16, color: AppColors.muted)),
          ],
          Text(after, style: appText(15, weight: FontWeight.w800)),
        ]),
      );
}
