import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/product.dart';
import '../core/theme.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import 'package:provider/provider.dart';

/// [20] ProdukHapus. Pops to the list once the product is deleted.
Future<void> confirmDeleteProduct(BuildContext context, Product p, {int? sold}) async {
  final repo = context.read<ProductRepository>();
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showAppSheet<bool>(
    context,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hapus ${p.name}?', style: appText(22, weight: FontWeight.w800, letterSpacing: -0.4)),
                  const SizedBox(height: 4),
                  Text('Tidak bisa dicatat lagi di Catat. Sisa stok ${p.stock} ikut terhapus.',
                      style: appText(14, color: AppColors.label)),
                ],
              ),
            ),
          ],
        ),
        if (sold != null && sold > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.paper, borderRadius: BorderRadius.circular(16)),
            child: Text('$sold jualan bulan ini tetap ada di Histori dan Laporan Analitik.',
                style: appText(13, weight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(flex: 10, child: SecondaryButton(label: 'Batal', onPressed: () => Navigator.pop(context, false))),
            const SizedBox(width: 12),
            Expanded(flex: 13, child: DangerButton(label: 'Ya, hapus', onPressed: () => Navigator.pop(context, true))),
          ],
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await repo.delete(p.id);
    router.pop();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(messageOf(e))));
  }
}
