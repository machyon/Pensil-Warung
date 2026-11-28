import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.labels, required this.selected, required this.onChanged, this.yellow = false});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  /// Settings style: chip track, 44 px yellow selected pill.
  final bool yellow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: yellow ? AppColors.chip : AppColors.disabled, borderRadius: BorderRadius.circular(yellow ? 20 : 22)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (yellow && i > 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Container(
                    height: yellow ? 44 : 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? (yellow ? AppColors.accent : AppColors.surface) : null,
                      borderRadius: BorderRadius.circular(yellow ? 16 : 18),
                      boxShadow: i == selected && !yellow ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))] : null,
                    ),
                    child: Text(
                      labels[i],
                      style: appText(15, weight: i == selected ? (yellow ? FontWeight.w800 : FontWeight.w700) : (yellow ? FontWeight.w500 : FontWeight.w600),
                          color: i == selected ? (yellow ? AppColors.onAccent : AppColors.ink) : (yellow ? AppColors.ink : AppColors.label)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
