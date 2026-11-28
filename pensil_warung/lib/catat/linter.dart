import '../domain/product.dart';
import 'fixes.dart';
import 'matcher.dart';
import 'numbers.dart';
import 'parser.dart';
import 'result.dart';

class _Item {
  _Item(this.name, this.price, this.stock, {this.product, this.created = false});
  String name;
  int price, stock;
  Product? product;
  bool created, deleted = false;
}

const notFoundMessage = 'Barang tidak ada di daftar';

/// Typed text -> per-line results and the ops to send. Simulates the batch the way the server
/// runs it: stock, prices, creates and deletes carry from line to line.
LintResult lint(String text, List<Product> products) {
  final items = <String, _Item>{
    for (final p in products) nameKey(p.name): _Item(p.name, p.price, p.stock, product: p),
  };
  _Item? find(String name) {
    final i = items[nameKey(name)];
    return i == null || i.deleted ? null : i;
  }

  final lines = <LineResult>[];
  final rows = text.split('\n');
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].trim().isEmpty) continue;
    final lineNo = i + 1;
    final raw = rows[i].trim();
    final p = parseLine(raw);

    LineResult make(LineStatus s, String msg, {
      _Item? item, Op? op, int? quantity, int? unitPrice, int? previousPrice, int? lineTotal,
      int? stockAfter, List<Fix> fixes = const [],
    }) =>
        LineResult(
          lineNo: lineNo, raw: raw, kind: p.kind, status: s, message: msg,
          product: item?.product, productName: item?.name ?? (p.nameTo > p.nameFrom ? p.name : null),
          quantity: quantity, unitPrice: unitPrice, previousPrice: previousPrice,
          lineTotal: lineTotal, stockAfter: stockAfter, reason: p.reason, hint: p.hint,
          op: op, fixes: fixes,
        );
    LineResult err(String msg, {_Item? item, List<Fix> fixes = const []}) =>
        make(LineStatus.error, msg, item: item, fixes: fixes);

    if (p.error != null) {
      lines.add(err(p.error!));
      continue;
    }

    if (p.kind == LineKind.createProduct) {
      final existing = find(p.name);
      if (existing != null) {
        lines.add(err(existing.created ? '${p.name} sudah ditulis di baris lain' : 'Nama sudah dipakai'));
        continue;
      }
      items[nameKey(p.name)] = _Item(p.name, p.price!, p.stock!, created: true);
      lines.add(make(LineStatus.ok, 'Barang baru',
          op: Op.createProduct(lineNo, p.name, p.price!, p.stock!),
          unitPrice: p.price, stockAfter: p.stock));
      continue;
    }

    final item = find(p.name);
    if (item == null) {
      lines.add(err(notFoundMessage, fixes: notFoundFixes(lineNo, p, _suggest(p.name, items))));
      continue;
    }
    final canonical = item.name;

    switch (p.kind) {
      case LineKind.sale:
        final q = p.qty!;
        if (q > item.stock) {
          lines.add(err('Stok cuma ${item.stock}, kurang ${q - item.stock}',
              item: item, fixes: stockFixes(lineNo, p, canonical, item.stock, q - item.stock)));
          break;
        }
        item.stock -= q;
        lines.add(make(p.warning == null ? LineStatus.ok : LineStatus.warning,
            p.warning ?? '$q × ${rupiah(item.price)}',
            item: item, op: Op.sale(lineNo, canonical, q), quantity: q, unitPrice: item.price,
            lineTotal: item.price * q, stockAfter: item.stock));
      case LineKind.restock:
        item.stock += p.qty!;
        lines.add(make(LineStatus.ok, 'Stok jadi ${item.stock}',
            item: item, op: Op.restock(lineNo, canonical, p.qty!), quantity: p.qty, stockAfter: item.stock));
      case LineKind.adjustDown:
        final q = p.qty!;
        if (q > item.stock) {
          lines.add(err('Stok cuma ${item.stock}, kurang ${q - item.stock}',
              item: item, fixes: adjustFixes(lineNo, p, item.stock)));
          break;
        }
        item.stock -= q;
        lines.add(make(LineStatus.ok, 'Stok jadi ${item.stock}',
            item: item, op: Op.adjustDown(lineNo, canonical, q, p.reason), quantity: q, stockAfter: item.stock));
      case LineKind.setPrice:
        final old = item.price;
        item.price = p.price!;
        lines.add(make(LineStatus.ok, '${rupiah(old)} → ${rupiah(p.price!)}',
            item: item, op: Op.setPrice(lineNo, canonical, p.price!), unitPrice: p.price, previousPrice: old));
      case LineKind.deleteProduct:
        item.deleted = true;
        lines.add(make(LineStatus.ok, 'Barang dihapus',
            item: item, op: Op.deleteProduct(lineNo, canonical), stockAfter: item.stock));
      case LineKind.createProduct:
        break; // handled above
    }
  }
  return LintResult.fromLines(lines);
}

String? _suggest(String name, Map<String, _Item> items) {
  final k = closestKey(nameKey(name), [for (final e in items.entries) if (!e.value.deleted) e.key]);
  return k == null ? null : items[k]!.name;
}

/// Puts each server `{line_no, code, message}` on its box line as an error, so a stock race the
/// client missed still shows on the right line.
LintResult mapServerLines(LintResult r, List<Map<String, dynamic>> serverLines) {
  final byNo = {for (final s in serverLines) s['line_no'] as int: s['message'] as String};
  return LintResult.fromLines([
    for (final l in r.lines) byNo.containsKey(l.lineNo) ? l.asError(byNo[l.lineNo]!) : l,
  ]);
}
