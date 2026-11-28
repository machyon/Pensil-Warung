import 'package:material_ui/material_ui.dart';

import '../format.dart';
import '../theme.dart';

/// "Bulan November 2026" with prev/next; tapping the label opens PilihBulan.
class MonthStepper extends StatelessWidget {
  const MonthStepper({
    super.key,
    required this.year,
    required this.month,
    this.onPrev,
    this.onNext,
    this.onPick,
  });

  final int year;
  final int month;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(tooltip: 'Bulan sebelumnya', onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: InkWell(
            onTap: onPick,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              child: Text('Bulan ${monthYear(year, month)}', style: appText(16, weight: FontWeight.w800)),
            ),
          ),
        ),
        IconButton(tooltip: 'Bulan berikutnya', onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}
