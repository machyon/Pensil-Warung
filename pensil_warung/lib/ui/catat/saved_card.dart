import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_card.dart';
import 'catat_view_model.dart';

/// [14] "Baru saja disimpan" card and the day line under it.
class SavedCardView extends StatelessWidget {
  const SavedCardView({super.key, required this.saved});

  final SavedCard saved;

  @override
  Widget build(BuildContext context) {
    final tx = saved.tx;
    final today = saved.today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 20, color: AppColors.onAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Baru saja disimpan', style: appText(16, weight: FontWeight.w800)),
                    Text('${wibTime(tx.occurredAt)} · ${tx.items.length} barang',
                        style: appText(13, color: AppColors.muted)),
                  ]),
                ),
                Text(rupiah(tx.total), style: appText(20, weight: FontWeight.w800)),
              ]),
              const SizedBox(height: 10),
              Text(tx.summary, style: appText(15, color: AppColors.label)),
              const SizedBox(height: 6),
              // Transaction detail arrives with the history branch.
              Text('Lihat atau ubah', style: appText(14, weight: FontWeight.w700, color: AppColors.faint)),
            ],
          ),
        ),
        if (today != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text('Hari ini: ${today.count} transaksi · ${rupiah(today.revenue)}',
                style: appText(14, weight: FontWeight.w600, color: AppColors.muted)),
          ),
      ],
    );
  }
}
