import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/session.dart';
import '../../domain/transaction.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/error_view.dart';
import '../core/widgets/product_avatar.dart';
import 'detail_view_model.dart';

/// [15] `TransaksiDetail`.
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        key: ValueKey(id),
        create: (c) => DetailViewModel(c.read<TransactionRepository>(), id),
        child: const _Body(),
      );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    final tx = vm.tx;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            BackHeader(title: 'Transaksi'),
            Expanded(
              child: tx == null
                  ? vm.error != null
                      ? ErrorView(error: vm.error!, onRetry: vm.load)
                      : const Center(child: CircularProgressIndicator())
                  : _Content(tx: tx),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductRepository>().items;
    final username = context.read<Session>().user?.username;
    final replaced = tx.voided && tx.replacedById != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Row(children: [
            Expanded(child: Text('${wibDateShort(tx.occurredAt)} · ${wibTime(tx.occurredAt)}', style: appText(14, color: AppColors.muted))),
            if (tx.voided) _Tag(replaced ? 'Diganti' : 'Dibatalkan'),
          ]),
        ),
        if (tx.voided)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              onTap: replaced ? () => context.push('/transaksi/${tx.replacedById}') : null,
              child: Row(children: [
                Expanded(
                  child: Text(
                    replaced
                        ? 'Transaksi ini sudah diganti dengan versi baru.'
                        : 'Transaksi ini dibatalkan${tx.voidReason == null ? '' : ': ${tx.voidReason}'}. Tidak dihitung dalam jualan.',
                    style: appText(14, color: AppColors.label),
                  ),
                ),
                if (replaced) Text('Lihat', style: appText(14, weight: FontWeight.w800)),
              ]),
            ),
          ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final (i, it) in tx.items.indexed) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  ProductAvatar(
                    name: it.name,
                    size: 44,
                    photoUrl: products.where((p) => p.id == it.productId).firstOrNull?.photoUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(it.name, style: appText(16, weight: FontWeight.w700)),
                      Text('${it.quantity} × ${rupiah(it.unitPrice)}', style: appText(13, color: AppColors.muted)),
                    ]),
                  ),
                  Text(rupiah(it.lineTotal), style: appText(16, weight: FontWeight.w700)),
                ]),
              ),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(children: [
                Expanded(child: Text('Total', style: appText(14, weight: FontWeight.w700, color: AppColors.label))),
                Text(rupiah(tx.total),
                    style: appText(22, weight: FontWeight.w800, letterSpacing: -0.4, color: tx.voided ? AppColors.faint : AppColors.ink)
                        .copyWith(decoration: tx.voided ? TextDecoration.lineThrough : null)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DITULIS DI CATAT', style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(14)),
              child: Text(tx.rawText, style: monoText(15).copyWith(height: 26 / 15)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _InfoRow('Dicatat oleh', username ?? '-'),
            const Divider(height: 1),
            _InfoRow('Riwayat ubahan', tx.history.isEmpty ? 'Belum pernah diubah' : '${tx.history.length} versi lama'),
            for (final h in tx.history) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Diubah ${wibRelative(h.revisedAt)}', style: appText(13, weight: FontWeight.w700, color: AppColors.muted))),
                    Text(rupiah(h.total), style: appText(15, weight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 4),
                  for (final it in h.items) Text('${it.name} ${it.quantity} × ${rupiah(it.unitPrice)}', style: appText(14, color: AppColors.label)),
                ]),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(label, style: appText(15, weight: FontWeight.w700))),
            Text(value, style: appText(15, color: AppColors.muted)),
          ]),
        ),
      );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: appText(12, weight: FontWeight.w700, color: AppColors.error)),
      );
}
