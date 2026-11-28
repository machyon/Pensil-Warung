import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/product_repository.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_header.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/product_avatar.dart';
import 'product_list_view_model.dart';
import '../notifications/notification_feed.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (c) => ProductListViewModel(c.read<ProductRepository>()),
        child: const _Body(),
      );
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add([String? name]) => context.push('/produk/tambah', extra: name);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ProductListViewModel>();
    final q = vm.query.trim();
    final shown = vm.shown;

    Widget body;
    if (vm.error != null) {
      body = EmptyState(
        icon: Icons.error_outline,
        title: 'Terjadi masalah',
        text: vm.error,
        actionLabel: 'Coba lagi',
        onAction: vm.load,
      );
    } else if (!vm.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (vm.total == 0) {
      body = EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Belum ada produk',
        text: 'Daftarkan barang yang kamu jual. Cukup nama, harga, dan stok.',
        actionLabel: 'Tambah barang',
        onAction: _add,
        footer: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ATAU KETIK DI CATAT',
                  style: appText(12, weight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.4)),
              const SizedBox(height: 6),
              Text('buat produk kerupuk harga 2000 stok 30', style: monoText(15)),
            ],
          ),
        ),
      );
    } else if (shown.isEmpty) {
      body = EmptyState(
        icon: Icons.search_off_rounded,
        title: '"$q" tidak ditemukan',
        text: 'Cek ejaannya, atau daftarkan sebagai barang baru.',
        actionLabel: 'Tambah "$q"',
        onAction: () => _add(q),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text('${shown.length} produk', style: appText(13, weight: FontWeight.w600, color: AppColors.muted)),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    InkWell(
                      onTap: () => context.push('/produk/${shown[i].id}', extra: shown[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.border)),
                        ),
                        child: Row(
                          children: [
                            ProductAvatar(name: shown[i].name, photoUrl: shown[i].photoUrl, size: 56, onPhotoError: () => context.read<ProductRepository>().photoFailed(shown[i].id)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(shown[i].name, style: appText(17, weight: FontWeight.w700)),
                                  Text(rupiah(shown[i].price), style: appText(14, color: AppColors.muted)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(12)),
                              child: Text('Stok ${shown[i].stock}',
                                  style: appText(13, weight: FontWeight.w700, color: AppColors.label)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              AppHeader(title: 'Produk', avatar: true, hasUnread: context.select<NotificationFeed, bool>((f) => f.hasUnread), onBell: () => context.push('/notifikasi')),
              if (vm.loaded && (vm.total > 0))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.only(left: 18, right: 6),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: AppColors.label),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: vm.setQuery,
                            style: appText(16),
                            decoration: InputDecoration(
                              hintText: 'Cari produk',
                              hintStyle: appText(16, color: AppColors.faint),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (vm.query.isNotEmpty)
                          IconButton(
                            tooltip: 'Hapus pencarian',
                            icon: const Icon(Icons.close_rounded, color: AppColors.label),
                            onPressed: () {
                              _search.clear();
                              vm.setQuery('');
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              Expanded(child: body),
            ],
          ),
          if (vm.loaded && shown.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 16,
              child: Material(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(18),
                elevation: 4,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _add,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, color: AppColors.onAccent),
                          const SizedBox(width: 8),
                          Text('Tambah', style: appText(16, weight: FontWeight.w700, color: AppColors.onAccent)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
