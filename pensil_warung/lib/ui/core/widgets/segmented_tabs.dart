import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.labels, required this.selected, required this.onChanged});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.disabled, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.surface : null,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: i == selected ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))] : null,
                    ),
                    child: Text(
                      labels[i],
                      style: appText(15, weight: i == selected ? FontWeight.w700 : FontWeight.w600,
                          color: i == selected ? AppColors.ink : AppColors.label),
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
