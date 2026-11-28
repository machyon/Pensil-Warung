import 'parser.dart';
import 'result.dart';

String _replaceLine(String text, int lineNo, String line) {
  final rows = text.split('\n');
  if (lineNo - 1 < rows.length) rows[lineNo - 1] = line;
  return rows.join('\n');
}

/// The line again with its name and/or quantity swapped.
String _rebuild(Parsed p, {String? name, int? qty}) {
  final tail = p.tokens.sublist(p.nameTo);
  return [
    ...p.tokens.sublist(0, p.nameFrom),
    name ?? p.name,
    if (qty != null) qty.toString(),
    ...(qty != null && p.qtyIdx != null ? tail.sublist(1) : tail),
  ].join(' ');
}

List<Fix> notFoundFixes(int lineNo, Parsed p, String? suggestion) {
  final name = p.name;
  final prefix = 'buat produk $name harga ';
  return [
    if (suggestion != null)
      Fix('Ganti jadi $suggestion', (t) => _replaceLine(t, lineNo, _rebuild(p, name: suggestion))),
    if (p.kind == LineKind.sale || p.kind == LineKind.restock)
      Fix(
        'Jadikan barang baru',
        (t) => _replaceLine(t, lineNo, '$prefix stok '),
        cursorAt: (t) {
          final rows = t.split('\n');
          return rows.take(lineNo - 1).fold(0, (s, r) => s + r.length + 1) + prefix.length;
        },
      ),
  ];
}

List<Fix> stockFixes(int lineNo, Parsed p, String name, int stock, int missing) => [
      if (stock > 0) Fix('Jual $stock saja', (t) => _replaceLine(t, lineNo, _rebuild(p, name: name, qty: stock))),
      Fix('Tambah stok $missing dulu', (t) {
        final rows = t.split('\n')..insert(lineNo - 1, 'tambah stok $name $missing');
        return rows.join('\n');
      }),
    ];

List<Fix> adjustFixes(int lineNo, Parsed p, int stock) => [
      if (stock > 0) Fix('Keluarkan $stock saja', (t) => _replaceLine(t, lineNo, _rebuild(p, qty: stock))),
    ];
