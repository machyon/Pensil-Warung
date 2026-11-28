import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/product.dart';
import '../../domain/transaction.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/product_avatar.dart';
import 'edit_view_model.dart';

/// [16] `TransaksiUbah`. Pops the new `Transaction` after a successful save.
class EditScreen extends StatelessWidget {
  const EditScreen({super.key, required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => EditViewModel(c.read<TransactionRepository>(), c.read<ProductRepository>(), tx),
    child: const _Body(),
  );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<EditViewModel>();
    final products = context.watch<ProductRepository>().items;
    final notes = vm.stockNotes;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const BackHeader(title: 'Ubah transaksi'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: Text(
                      '${wibDateShort(vm.tx.occurredAt)} · ${wibTime(vm.tx.occurredAt)}',
                      style: appText(14, color: AppColors.muted),
                    ),
                  ),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < vm.lines.length; i++) ...[
                          _LineTile(index: i, vm: vm, photo: products.where((p) => p.id == vm.lines[i].productId).firstOrNull?.photoUrl),
                          const Divider(height: 1),
                        ],
                        InkWell(
                          onTap: () async {
                            final p = await _pickProduct(context, products);
                            if (p != null) vm.add(p);
                          },
                          child: Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(Icons.add, size: 20),
                                const SizedBox(width: 10),
                                Text('Tambah barang ke transaksi', style: appText(15, weight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SETELAH DISIMPAN',
                          style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Total',
                                  style: appText(13, weight: FontWeight.w600, color: AppColors.muted),
                                ),
                              ),
                              Text(
                                rupiah(vm.tx.total),
                                style: appText(
                                  15,
                                  weight: FontWeight.w600,
                                  color: AppColors.muted,
                                ).copyWith(decoration: vm.changed ? TextDecoration.lineThrough : null),
                              ),
                              if (vm.changed) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(Icons.arrow_forward, size: 16, color: AppColors.muted),
                                ),
                                Text(rupiah(vm.newTotal), style: appText(16, weight: FontWeight.w800)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          notes.isEmpty
                              ? vm.changed
                                    ? 'Stok tidak berubah. Transaksi asli tetap tercatat di riwayat ubahan.'
                                    : 'Belum ada yang diubah.'
                              : 'Stok ${notes.join(', ')}. Transaksi asli tetap tercatat di riwayat ubahan.',
                          style: appText(13, color: AppColors.label),
                        ),
                      ],
                    ),
                  ),
                  if (vm.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                      child: Text(
                        vm.error!,
                        style: appText(14, weight: FontWeight.w600, color: AppColors.error),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: PrimaryButton(
                label: 'Simpan perubahan',
                busy: vm.running,
                onPressed: vm.changed
                    ? () async {
                        final t = await vm.save();
                        if (t != null && context.mounted) context.pop(t);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.index, required this.vm, this.photo});
  final int index;
  final EditViewModel vm;
  final String? photo;

  @override
  Widget build(BuildContext context) {
    final l = vm.lines[index];
    final note = l.itemId == null
        ? 'baru'
        : l.qty == l.oldQty
        ? 'tidak berubah'
        : 'semula ${l.oldQty}';
    final err = vm.rowErrors[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              ProductAvatar(name: l.name, size: 44, photoUrl: photo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.name, style: appText(16, weight: FontWeight.w700)),
                    Text('${rupiah(l.unitPrice)} · $note', style: appText(13, color: AppColors.muted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hapus ${l.name} dari transaksi',
                onPressed: vm.canRemove ? () => vm.remove(index) : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    children: [
                      _StepButton(icon: Icons.remove, label: 'Kurangi', onTap: l.qty > 1 ? () => vm.setQty(index, l.qty - 1) : null),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${l.qty}',
                          textAlign: TextAlign.center,
                          style: appText(18, weight: FontWeight.w800),
                        ),
                      ),
                      _StepButton(icon: Icons.add, label: 'Tambah', onTap: () => vm.setQty(index, l.qty + 1)),
                    ],
                  ),
                ),
                const Spacer(),
                Text(rupiah(l.qty * l.unitPrice), style: appText(16, weight: FontWeight.w700)),
              ],
            ),
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  err,
                  style: appText(13, weight: FontWeight.w600, color: AppColors.error),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, size: 18, color: onTap == null ? AppColors.faint : AppColors.ink),
      ),
    ),
  );
}

Future<Product?> _pickProduct(BuildContext context, List<Product> all) =>
    showAppSheet<Product>(context, builder: (_) => _ProductPicker(all: all));

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.all});
  final List<Product> all;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.all.where((p) => p.name.toLowerCase().contains(_q.toLowerCase())).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tambah barang', style: appText(20, weight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          autofocus: false,
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Cari barang',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: AppColors.paper,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 340,
          child: shown.isEmpty
              ? Center(
                  child: Text('Barang tidak ditemukan', style: appText(15, color: AppColors.muted)),
                )
              : ListView(
                  children: [
                    for (final p in shown)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ProductAvatar(name: p.name, size: 44, photoUrl: p.photoUrl),
                        title: Text(p.name, style: appText(16, weight: FontWeight.w700)),
                        subtitle: Text('${rupiah(p.price)} · stok ${p.stock}', style: appText(13, color: AppColors.muted)),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
