import 'numbers.dart';

enum LineKind { sale, restock, adjustDown, createProduct, setPrice, deleteProduct }

/// One op of `POST /catat`; `toJson` is the exact wire shape (`docs/api.md`).
class Op {
  const Op.sale(this.lineNo, String this.product, int this.quantity)
      : op = 'sale', name = null, price = null, stock = null, note = null;
  const Op.restock(this.lineNo, String this.product, int this.quantity)
      : op = 'restock', name = null, price = null, stock = null, note = null;
  const Op.adjustDown(this.lineNo, String this.product, int this.quantity, this.note)
      : op = 'adjust_down', name = null, price = null, stock = null;
  const Op.setPrice(this.lineNo, String this.product, int this.price)
      : op = 'set_price', name = null, quantity = null, stock = null, note = null;
  const Op.createProduct(this.lineNo, String this.name, int this.price, int this.stock)
      : op = 'create_product', product = null, quantity = null, note = null;
  const Op.deleteProduct(this.lineNo, String this.product)
      : op = 'delete_product', name = null, quantity = null, price = null, stock = null, note = null;

  final int lineNo;
  final String op;
  final String? product, name, note;
  final int? quantity, price, stock;

  Map<String, dynamic> toJson() => {
        'line_no': lineNo,
        'op': op,
        if (product != null) 'product': product,
        if (name != null) 'name': name,
        if (quantity != null) 'quantity': quantity,
        if (price != null) 'price': price,
        if (stock != null) 'stock': stock,
        if (note != null) 'note': note,
      };
}

/// A typed line split into its parts, before any product lookup.
class Parsed {
  Parsed(this.kind, this.tokens, {this.nameFrom = 0, this.nameTo = 0});

  final LineKind kind;
  final List<String> tokens;
  final int nameFrom, nameTo; // token range of the product name
  int? qty, price, stock, qtyIdx;
  String? reason, error, hint, warning;

  String get name => tokens.sublist(nameFrom, nameTo).join(' ');
}

const createExample = 'buat produk kerupuk harga 2000 stok 30';
const _tooBig = 'Angka terlalu besar';

/// Reads [t] as a whole number >= 0, or returns the error message for [label].
(int?, String?) _int(String t, String label) {
  final n = parseNumber(t);
  return switch (n.kind) {
    NumKind.integer => n.value < 0 ? (null, _tooBig) : (n.value, null),
    NumKind.decimal => (null, '$label harus bilangan bulat'),
    NumKind.none => (null, '$label belum ditulis'),
  };
}

/// `<name> <qty>` over tokens [from, end). [needQty] false is the sale rule (no number = warning, 1).
Parsed _nameQty(LineKind kind, List<String> t, int from, int end, {required bool needQty}) {
  final last = end > from ? parseNumber(t[end - 1]) : const ParsedNumber(NumKind.none);
  final hasNum = last.kind != NumKind.none;
  final p = Parsed(kind, t, nameFrom: from, nameTo: hasNum ? end - 1 : end);
  if (hasNum) p.qtyIdx = end - 1;
  if (p.nameTo <= p.nameFrom) {
    p.error = 'Nama barang belum ditulis';
  } else if (!hasNum && needQty) {
    p.error = 'Jumlah belum ditulis';
  } else if (!hasNum) {
    p.qty = 1;
    p.warning = 'Jumlah tidak ditulis, dianggap 1';
  } else if (last.kind == NumKind.decimal) {
    p.error = 'Jumlah harus bilangan bulat';
  } else if (last.value < 1 || last.value > 999999999) {
    p.error = 'Jumlah harus 1 sampai 999.999.999';
  } else {
    p.qty = last.value;
  }
  return p;
}

Parsed parseLine(String raw) {
  final t = tokenize(raw);
  final l = [for (final x in t) x.toLowerCase()];
  bool starts(String a, [String? b]) => l.isNotEmpty && l[0] == a && (b == null || (l.length > 1 && l[1] == b));

  if (starts('tambah', 'stok')) return _nameQty(LineKind.restock, t, 2, t.length, needQty: true);

  if (starts('hapus', 'stok')) {
    final a = l.indexOf('alasan', 3); // needs a name and a number before it
    final p = _nameQty(LineKind.adjustDown, t, 2, a < 0 ? t.length : a, needQty: true);
    if (a >= 0 && a + 1 < t.length) p.reason = t.sublist(a + 1).join(' ');
    return p;
  }

  if (starts('buat', 'produk')) {
    final h = l.indexOf('harga', 2);
    final p = Parsed(LineKind.createProduct, t, nameFrom: 2, nameTo: h < 0 ? t.length : h);
    if (p.nameTo <= 2) {
      p.error = 'Nama barang belum ditulis';
      return p;
    }
    final s = h < 0 ? -1 : l.indexOf('stok', h + 1);
    final priceEnd = s < 0 ? t.length : s;
    if (h < 0 || h + 1 >= priceEnd) {
      p.error = 'Harga belum ditulis';
      p.hint = createExample;
      return p;
    }
    final (price, e1) = _int(t[h + 1], 'Harga');
    if (e1 != null) return p..error = e1;
    p.price = price;
    if (s < 0) {
      p.stock = 0;
    } else {
      final (stock, e2) = s + 1 < t.length ? _int(t[s + 1], 'Stok') : (null, 'Stok belum ditulis');
      if (e2 != null) return p..error = e2;
      p.stock = stock;
    }
    return p;
  }

  if (starts('ubah', 'harga')) {
    final hasPrice = t.length > 2 && parseNumber(t.last).kind != NumKind.none;
    final p = Parsed(LineKind.setPrice, t, nameFrom: 2, nameTo: hasPrice ? t.length - 1 : t.length);
    if (p.nameTo <= 2) return p..error = 'Nama barang belum ditulis';
    if (!hasPrice) return p..error = 'Harga belum ditulis';
    final (price, e) = _int(t.last, 'Harga');
    return p
      ..price = price
      ..error = e;
  }

  if (starts('hapus')) {
    final p = Parsed(LineKind.deleteProduct, t, nameFrom: 1, nameTo: t.length);
    if (t.length < 2) p.error = 'Nama barang belum ditulis';
    return p;
  }

  return _nameQty(LineKind.sale, t, 0, t.length, needQty: false);
}
