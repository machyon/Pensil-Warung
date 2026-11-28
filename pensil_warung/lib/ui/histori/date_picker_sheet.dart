import 'package:material_ui/material_ui.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../domain/analytics.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets/app_sheet.dart';
import '../core/widgets/buttons.dart';
import 'histori_view_model.dart';

/// [13] `PilihTanggal`: a month grid. Only days with sales (up to today) can be picked.
/// Returns the picked `YYYY-MM-DD`.
Future<String?> showDatePickerSheet(BuildContext context, AnalyticsRepository repo, String selected) =>
    showAppSheet<String>(context, builder: (_) => _DatePicker(repo: repo, selected: selected));

class _DatePicker extends StatefulWidget {
  const _DatePicker({required this.repo, required this.selected});
  final AnalyticsRepository repo;
  final String selected;

  @override
  State<_DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends State<_DatePicker> {
  late String _month = widget.selected.substring(0, 7);
  late String? _sel = widget.selected;
  Map<String, DayTotal> _days = {};
  String _first = HistoriViewModel.currentMonth;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMonth();
    widget.repo.months().then((m) {
      if (mounted && m.isNotEmpty) setState(() => _first = m.last.month);
    }, onError: (_) {});
  }

  Future<void> _loadMonth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.repo.days(_month);
      if (mounted) setState(() => _days = {for (final x in d) x.day: x});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _go(int delta) {
    _month = monthKey(monthIndex(_month) + delta);
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final idx = monthIndex(_month);
    final y = idx ~/ 12, m = idx % 12 + 1;
    final lead = DateTime.utc(y, m, 1).weekday - 1; // Monday first
    final count = DateTime.utc(y, m + 1, 0).day;
    final picked = _sel == null ? null : _days[_sel];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          IconButton(tooltip: 'Bulan sebelumnya', onPressed: idx > monthIndex(_first) ? () => _go(-1) : null, icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(monthYear(y, m), textAlign: TextAlign.center, style: appText(18, weight: FontWeight.w800))),
          IconButton(
              tooltip: 'Bulan berikutnya',
              onPressed: idx < monthIndex(HistoriViewModel.currentMonth) ? () => _go(1) : null,
              icon: const Icon(Icons.chevron_right)),
        ]),
        Row(children: [
          for (final d in const ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'])
            Expanded(child: Center(child: Text(d, style: appText(12, weight: FontWeight.w700, color: AppColors.faint)))),
        ]),
        const SizedBox(height: 4),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Tidak bisa memuat tanggal. Coba lagi.', style: appText(14, color: AppColors.muted))))
        else
          Opacity(
            opacity: _loading ? 0.4 : 1,
            child: GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < lead; i++) const SizedBox(),
                for (var d = 1; d <= count; d++) _cell('$y-${two(m)}-${two(d)}', d),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          picked == null ? 'Hanya tanggal yang ada jualannya bisa dipilih.' : '${picked.count} transaksi · ${rupiah(picked.revenue)}',
          style: appText(14, weight: FontWeight.w600, color: AppColors.label),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(flex: 2, child: SecondaryButton(label: 'Batal', onPressed: () => Navigator.pop(context))),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: PrimaryButton(
              label: picked == null ? 'Lihat transaksi' : 'Lihat ${dayShort(picked.day)}',
              onPressed: picked == null ? null : () => Navigator.pop(context, picked.day),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _cell(String iso, int d) {
    final enabled = _days.containsKey(iso), on = iso == _sel;
    return Semantics(
      button: true,
      selected: on,
      enabled: enabled,
      label: '${dayLong(iso)}${enabled ? '' : ', tidak ada jualan'}',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? () => setState(() => _sel = iso) : null,
        child: Container(
          margin: const EdgeInsets.all(3),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? AppColors.accent : null, shape: BoxShape.circle),
          child: Text('$d',
              style: appText(15,
                  weight: enabled ? FontWeight.w700 : FontWeight.w500,
                  color: on ? AppColors.onAccent : enabled ? AppColors.ink : AppColors.faint)),
        ),
      ),
    );
  }
}
