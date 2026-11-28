import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import 'histori_view_model.dart';

const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

/// [14] `PilihBulan`. Months outside [first]..[last] (both `YYYY-MM`) are struck through.
Future<String?> showMonthPicker(BuildContext context, {required String selected, required String first, required String last}) =>
    showAppSheet<String>(context, builder: (_) => _MonthPicker(selected: selected, first: first, last: last));

class _MonthPicker extends StatefulWidget {
  const _MonthPicker({required this.selected, required this.first, required this.last});
  final String selected, first, last;

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  late int _sel = monthIndex(widget.selected);
  late int _year = _sel ~/ 12;

  @override
  Widget build(BuildContext context) {
    final min = monthIndex(widget.first), max = monthIndex(widget.last);
    final firstLabel = monthYear(min ~/ 12, min % 12 + 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          IconButton(
            tooltip: 'Tahun sebelumnya',
            onPressed: _year * 12 > min ? () => setState(() => _year--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(child: Text('$_year', textAlign: TextAlign.center, style: appText(20, weight: FontWeight.w800))),
          IconButton(
            tooltip: 'Tahun berikutnya',
            onPressed: (_year + 1) * 12 <= max ? () => setState(() => _year++) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.2,
          children: [
            for (var i = 0; i < 12; i++) _cell(i, _year * 12 + i, min, max),
          ],
        ),
        const SizedBox(height: 16),
        Text('Catatan dimulai $firstLabel. Bulan yang belum lewat belum bisa dipilih.',
            style: appText(13, color: AppColors.label)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(flex: 2, child: SecondaryButton(label: 'Batal', onPressed: () => Navigator.pop(context))),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: PrimaryButton(
              label: _sel == max ? 'Lihat bulan ini' : 'Lihat ${monthNames[_sel % 12]}',
              onPressed: () => Navigator.pop(context, monthKey(_sel)),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _cell(int i, int t, int min, int max) {
    final disabled = t < min || t > max, on = t == _sel, current = t == max;
    return Semantics(
      button: true,
      selected: on,
      enabled: !disabled,
      label: '${monthNames[i]} ${t ~/ 12}${disabled ? ', belum bisa dipilih' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : () => setState(() => _sel = t),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.accent : disabled ? AppColors.paper : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: current ? AppColors.ink : on ? AppColors.accent : AppColors.border, width: current ? 2 : 1),
          ),
          child: Text(
            _short[i],
            style: appText(16,
                weight: on || current ? FontWeight.w800 : FontWeight.w600,
                color: on ? AppColors.onAccent : disabled ? AppColors.faint : AppColors.ink)
                .copyWith(decoration: disabled ? TextDecoration.lineThrough : null),
          ),
        ),
      ),
    );
  }
}
