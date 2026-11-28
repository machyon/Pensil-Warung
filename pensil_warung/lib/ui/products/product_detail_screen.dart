import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../../domain/product.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/error_view.dart';
import '../core/widgets/product_avatar.dart';
import '../photos/photo_flow.dart';
import 'product_actions.dart';
import 'product_detail_view_model.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.id, this.initial});

  final int id;
  final Product? initial;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => ProductDetailViewModel(c.read<ProductRepository>(), id, initial),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) context.read<ProductDetailViewModel>().loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductDetailViewModel>();
    final p = vm.product;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const BackHeader(title: ''),
            Expanded(
              child: p == null
                  ? (vm.error != null
                      ? ErrorView(error: vm.error!, onRetry: vm.load)
                      : const Center(child: CircularProgressIndicator()))
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            children: [
                              Semantics(
                                button: true,
                                label: p.photoUrl == null ? 'Tambah foto ${p.name}' : 'Ganti foto ${p.name}',
                                child: GestureDetector(
                                  onTap: () async {
                                    if (await changeProductPhoto(context, p)) vm.refreshProduct();
                                  },
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ProductAvatar(
                                        name: p.name,
                                        photoUrl: p.photoUrl,
                                        size: 96,
                                        onPhotoError: vm.photoFailed,
                                      ),
                                      Positioned(
                                        right: -4,
                                        bottom: -4,
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: AppColors.accent,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppColors.paper, width: 2),
                                          ),
                                          child: const Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.onAccent),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: appText(28, weight: FontWeight.w800, letterSpacing: -0.5)),
                                    Text(rupiah(p.price), style: appText(20, weight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (vm.photoPending)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                              decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(16)),
                              child: Row(children: [
                                Expanded(child: Text('Foto belum terunggah', style: appText(14, weight: FontWeight.w700, color: AppColors.error))),
                                TextButton(
                                  onPressed: vm.retrying ? null : vm.retryPhoto,
                                  child: Text(vm.retrying ? 'Mengunggah...' : 'Coba lagi',
                                      style: appText(14, weight: FontWeight.w800, color: AppColors.error)),
                                ),
                              ]),
                            ),
                          ),
                        Row(children: [
                          Expanded(child: _Stat('Stok sekarang', '${p.stock}')),
                          const SizedBox(width: 10),
                          Expanded(child: _Stat('Terjual bulan ini', vm.sold?.toString() ?? '–')),
                        ]),
                        const SizedBox(height: 10),
                        _Stat(
                          'Pendapatan bulan ini',
                          vm.revenue == null ? '–' : rupiah(vm.revenue!),
                          size: 22,
                          trailing: vm.rank == null ? null : 'Terlaris ke-${vm.rank}',
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('RIWAYAT STOK',
                              style: appText(13, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < vm.movements.length; i++) _MovementRow(vm.movements[i], first: i == 0),
                              if (vm.loadingMore)
                                const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            if (p != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 10,
                      child: _BarButton(
                        label: 'Hapus',
                        fg: const Color(0xFFB3261E),
                        bg: AppColors.surface,
                        bordered: true,
                        onTap: () => confirmDeleteProduct(context, p, sold: vm.sold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 13,
                      child: _BarButton(
                        label: 'Ubah',
                        fg: AppColors.onAccent,
                        bg: AppColors.accent,
                        icon: Icons.edit_outlined,
                        onTap: () async {
                          await context.push('/produk/${p.id}/ubah', extra: p);
                          if (context.mounted) vm.load();
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
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.size = 26, this.trailing});

  final String label;
  final String value;
  final double size;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
                  Text(value, style: appText(size, weight: FontWeight.w800, letterSpacing: -0.5)),
                ],
              ),
            ),
            if (trailing != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
                child: Text(trailing!, style: appText(13, weight: FontWeight.w700, color: AppColors.label)),
              ),
          ],
        ),
      );
}

class _MovementRow extends StatelessWidget {
  const _MovementRow(this.m, {required this.first});

  final StockMovement m;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: AppColors.chip, shape: BoxShape.circle),
              child: Icon(m.delta >= 0 ? Icons.add_rounded : Icons.remove_rounded, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.label, style: appText(15, weight: FontWeight.w700)),
                  Text(wibRelative(m.createdAt), style: appText(13, color: AppColors.muted)),
                ],
              ),
            ),
            Text(m.delta > 0 ? '+${m.delta}' : '−${m.delta.abs()}', style: appText(15, weight: FontWeight.w700)),
          ],
        ),
      );
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.fg,
    required this.bg,
    required this.onTap,
    this.bordered = false,
    this.icon,
  });

  final String label;
  final Color fg, bg;
  final bool bordered;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: bordered ? const BorderSide(color: AppColors.border) : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
                Text(label, style: appText(16, weight: FontWeight.w700, color: fg)),
              ],
            ),
          ),
        ),
      );
}
