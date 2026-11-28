import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../domain/product.dart';
import '../core/format.dart';
import '../core/money_input.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import '../core/widgets/buttons.dart';
import '../core/widgets/labeled_field.dart';
import '../core/widgets/product_avatar.dart';
import '../photos/photo_flow.dart';
import 'product_edit_view_model.dart';

class ProductEditScreen extends StatelessWidget {
  const ProductEditScreen({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => ProductEditViewModel(c.read<ProductRepository>(), product),
        child: _Body(product),
      );
}

class _Body extends StatefulWidget {
  const _Body(this.product);

  final Product product;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _price = TextEditingController(text: groupedDigits(widget.product.price));
  late final _stock = TextEditingController(text: '${widget.product.stock}');

  @override
  void initState() {
    super.initState();
    final vm = context.read<ProductEditViewModel>();
    vm
      ..name = _name.text
      ..price = _price.text
      ..stock = _stock.text;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductEditViewModel>();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Batal ubah, kembali ke detail',
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Text('Ubah produk', style: appText(26, weight: FontWeight.w800, letterSpacing: -0.5)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        ProductAvatar(name: widget.product.name, photoUrl: vm.photoUrl, size: 64),
                        const SizedBox(width: 14),
                        Expanded(
                          child: SecondaryButton(
                            label: vm.photoUrl == null ? 'Tambah foto' : 'Ganti foto',
                            onPressed: () async {
                              if (await changeProductPhoto(context, widget.product)) vm.refreshPhoto();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      LabeledField(
                        label: 'Nama barang',
                        controller: _name,
                        helper: 'Nama ini yang dikenali saat kamu ketik di Catat.',
                        error: vm.nameError,
                        textInputAction: TextInputAction.next,
                        onChanged: (v) {
                          vm.name = v;
                          vm.edited();
                        },
                      ),
                      const SizedBox(height: 16),
                      LabeledField(
                        label: 'Harga',
                        controller: _price,
                        prefix: 'Rp',
                        keyboardType: TextInputType.number,
                        inputFormatters: const [RupiahInputFormatter()],
                        helper: vm.priceChanged
                            ? 'Semula ${rupiah(widget.product.price)}. Jualan yang sudah tercatat tetap pakai harga lama.'
                            : null,
                        onChanged: (v) {
                          vm.price = v;
                          vm.edited();
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      LabeledField(
                        label: 'Stok',
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        helper: 'Pakai ini kalau hitungan stok di warung beda dengan aplikasi.',
                        onChanged: (v) {
                          vm.stock = v;
                          vm.edited();
                        },
                      ),
                      if (vm.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(vm.error!, style: appText(14, weight: FontWeight.w700, color: AppColors.error)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: PrimaryButton(
                label: 'Simpan',
                busy: vm.running,
                onPressed: () async {
                  if (await vm.save() && context.mounted) context.pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
