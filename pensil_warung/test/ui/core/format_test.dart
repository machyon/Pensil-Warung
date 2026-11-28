import 'package:flutter_test/flutter_test.dart';
import 'package:pensil_warung/ui/core/format.dart';

void main() {
  test('rupiah groups with dots', () {
    expect(rupiah(0), 'Rp0');
    expect(rupiah(15000), 'Rp15.000');
    expect(rupiah(1234567), 'Rp1.234.567');
    expect(rupiah(-2500), '-Rp2.500');
  });

  test('rupiahCompact', () {
    expect(rupiahCompact(500), '500');
    expect(rupiahCompact(887000), '887rb');
    expect(rupiahCompact(999600), '1jt');
    expect(rupiahCompact(1000000), '1jt');
    expect(rupiahCompact(1234567), '1,2jt');
    expect(rupiahCompact(28700000), '28,7jt');
  });

  test('wib shifts UTC by +7 and crosses midnight', () {
    final t = DateTime.utc(2026, 11, 26, 20, 5); // 03.05 on the 27th in WIB
    expect(wibTime(t), '03.05');
    expect(wibDate(t), 'Jumat, 27 November 2026');
    expect(wibIsoDate(t), '2026-11-27');
  });

  test('names and month label', () {
    expect(dayNames.length, 7);
    expect(monthNames[11], 'Desember');
    expect(monthYear(2026, 1), 'Januari 2026');
  });
}
