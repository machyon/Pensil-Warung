import 'package:intl/intl.dart';

const dayNames = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const monthNames = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

final _grouped = NumberFormat.decimalPattern('id_ID');

/// 15000 -> `Rp15.000`. Whole rupiah only.
String rupiah(int n) => n < 0 ? '-Rp${_grouped.format(-n)}' : 'Rp${_grouped.format(n)}';

/// 887000 -> `887rb`, 1234567 -> `1,2jt`, 28700000 -> `28,7jt`.
String rupiahCompact(int n) {
  if (n < 0) return '-${rupiahCompact(-n)}';
  if (n < 1000) return '$n';
  final rb = (n + 500) ~/ 1000;
  if (rb < 1000) return '${rb}rb';
  final tenths = (n + 50000) ~/ 100000; // jt with one decimal
  final whole = tenths ~/ 10, frac = tenths % 10;
  return frac == 0 ? '${whole}jt' : '$whole,${frac}jt';
}

/// The API sends UTC; WIB is a fixed +07:00 (no DST). The result's fields are
/// the WIB wall clock (it is flagged UTC only so no local zone is applied again).
DateTime wib(DateTime t) => t.toUtc().add(const Duration(hours: 7));

String two(int n) => n.toString().padLeft(2, '0');

/// `08.05`
String wibTime(DateTime t) {
  final w = wib(t);
  return '${two(w.hour)}.${two(w.minute)}';
}

/// `Kamis, 26 November 2026`
String wibDate(DateTime t) {
  final w = wib(t);
  return '${dayNames[w.weekday - 1]}, ${w.day} ${monthNames[w.month - 1]} ${w.year}';
}

/// `Selasa, 17 Nov 2026`
String wibDateShort(DateTime t) {
  final w = wib(t);
  return '${dayNames[w.weekday - 1]}, ${w.day} ${monthNames[w.month - 1].substring(0, 3)} ${w.year}';
}

/// `2026-11-26`, the WIB date sent as `date=`.
String wibIsoDate(DateTime t) {
  final w = wib(t);
  return '${w.year}-${two(w.month)}-${two(w.day)}';
}

/// `November 2026`
String monthYear(int year, int month) => '${monthNames[month - 1]} $year';

/// `Hari ini, 14.32`, `Kemarin, 21.40`, `Sen, 16 Nov, 08.00` (WIB). [now] is for tests.
String wibRelative(DateTime t, {DateTime? now}) {
  final w = wib(t), n = wib(now ?? DateTime.now());
  final days = DateTime.utc(n.year, n.month, n.day).difference(DateTime.utc(w.year, w.month, w.day)).inDays;
  final time = wibTime(t);
  if (days == 0) return 'Hari ini, $time';
  if (days == 1) return 'Kemarin, $time';
  return '${dayNames[w.weekday - 1].substring(0, 3)}, ${w.day} ${monthNames[w.month - 1].substring(0, 3)}, $time';
}

/// `15000` -> `15.000`, the Rp field's text.
String groupedDigits(int n) => _grouped.format(n);
