import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../core/money_input.dart';
import '../core/theme.dart';
import '../core/widgets/buttons.dart';
import 'bulk_add_view_model.dart';

class BulkAddScreen extends StatelessWidget {
  const BulkAddScreen({super.key, this.firstName});

  /// Name typed in the search that found nothing.
  final String? firstName;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => BulkAddViewModel(c.read<ProductRepository>(), firstName: firstName),
        child: const _Body(),
      );
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BulkAddViewModel>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: IconButton(
                  tooltip: 'Kembali',
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tambah barang dagangan', style: appText(26, weight: FontWeight.w800, letterSpacing: -0.5)),
                          const SizedBox(height: 6),
                          Text('Isi nama, harga, dan stok. Satu barang sudah cukup untuk mulai.',
                              style: appText(15, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                            child: Row(children: [
                              Expanded(child: _head('Barang')),
                              SizedBox(width: 108, child: _head('Harga')),
                              SizedBox(width: 56, child: _head('Stok')),
                              const SizedBox(width: 36),
                            ]),
                          ),
                          for (var i = 0; i < vm.rows.length; i++) _RowView(vm.rows[i], first: i == 0),
                          InkWell(
                            onTap: vm.add,
                            child: Container(
                              height: 52,
                              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                              child: Row(children: [
                                const SizedBox(width: 2),
                                const Icon(Icons.add_rounded),
                                const SizedBox(width: 10),
                                Text('Tambah barang lain', style: appText(15, weight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (vm.error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                        child: Text(vm.error!, style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
                      ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text.rich(
                        TextSpan(style: appText(14, color: AppColors.label), children: [
                          TextSpan(text: 'Stok', style: appText(14, weight: FontWeight.w700)),
                          const TextSpan(text: ' = jumlah yang siap dijual. Jualan ditolak kalau stok tidak cukup.'),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Siap disimpan', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
                        Text('${vm.readyCount} barang', style: appText(22, weight: FontWeight.w800, letterSpacing: -0.4)),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: PrimaryButton(
                      label: 'Simpan',
                      busy: vm.running,
                      onPressed: vm.readyCount == 0
                          ? null
                          : () async {
                              if (await vm.save() && context.mounted) context.pop();
                            },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head(String t) =>
      Text(t.toUpperCase(), style: appText(12, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4));
}

class _RowView extends StatelessWidget {
  const _RowView(this.row, {required this.first});

  final BulkRow row;
  final bool first;

  Widget _box(Widget child, {bool error = false}) => Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: error ? AppColors.error : AppColors.fieldBorder, width: error ? 2 : 1),
        ),
        child: child,
      );

  InputDecoration _plain(String? hint) => InputDecoration(
        border: InputBorder.none,
        isCollapsed: true,
        hintText: hint,
        hintStyle: appText(16, color: AppColors.faint),
      );

  @override
  Widget build(BuildContext context) {
    final vm = context.read<BulkAddViewModel>();
    final note = row.nameError ?? row.skipNote;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _box(
                  error: row.nameError != null,
                  TextField(
                    controller: row.nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => vm.edited(row),
                    style: appText(15),
                    decoration: _plain('Nama barang'),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 102,
                child: _box(Row(children: [
                  Text('Rp', style: appText(14, weight: FontWeight.w600, color: AppColors.muted)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: row.priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [RupiahInputFormatter()],
                      onChanged: (_) => vm.edited(row),
                      style: appText(16),
                      decoration: _plain('0'),
                    ),
                  ),
                ])),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 50,
                child: _box(TextField(
                  controller: row.stockCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  textAlign: TextAlign.center,
                  onChanged: (_) => vm.edited(row),
                  style: appText(16),
                  decoration: _plain('0'),
                )),
              ),
              SizedBox(
                width: 36,
                child: IconButton(
                  tooltip: 'Hapus baris',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                  onPressed: () => vm.remove(row),
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(note,
                  style: row.nameError != null
                      ? appText(13, weight: FontWeight.w700, color: AppColors.error)
                      : appText(13, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }
}
