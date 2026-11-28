import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/product.dart';
import '../../domain/transaction.dart';

/// A line of the sale being edited. [itemId] is null for a line added in this edit.
class EditLine {
  EditLine({this.itemId, required this.productId, required this.name, required this.unitPrice, required this.oldQty, required this.qty});
  final int? itemId;
  final int? productId;
  final String name;
  final int unitPrice, oldQty;
  int qty;
}

/// `Nasi goreng kembali 1 (18 jadi 19)`: what the edit does to stock, from the cached stock.
/// [stock] maps product id to its current stock; [names] to its name.
List<String> stockChanges(List<TxItem> before, List<EditLine> after, Map<int, int> stock, Map<int, String> names) {
  final delta = <int, int>{};
  for (final i in before) {
    if (i.productId != null) delta[i.productId!] = (delta[i.productId!] ?? 0) + i.quantity;
  }
  for (final l in after) {
    if (l.productId != null) delta[l.productId!] = (delta[l.productId!] ?? 0) - l.qty;
  }
  return [
    for (final e in delta.entries)
      if (e.value != 0 && stock.containsKey(e.key))
        '${names[e.key]} ${e.value > 0 ? 'kembali' : 'berkurang'} ${e.value.abs()} (${stock[e.key]} jadi ${stock[e.key]! + e.value})',
  ];
}

class EditViewModel extends ChangeNotifier {
  EditViewModel(this._repo, this._products, this.tx)
    : lines = [
        for (final i in tx.items)
          EditLine(itemId: i.id, productId: i.productId, name: i.name, unitPrice: i.unitPrice, oldQty: i.quantity, qty: i.quantity),
      ] {
    if (!_products.loaded) _products.load().catchError((_) {});
  }

  final TransactionRepository _repo;
  final ProductRepository _products;
  final Transaction tx;
  final List<EditLine> lines;

  bool running = false;
  String? error;

  /// Server messages by line index (`lines_invalid`, `line_no` - 1).
  final rowErrors = <int, String>{};
  String? _uuid;

  int get newTotal => lines.fold(0, (a, l) => a + l.qty * l.unitPrice);
  bool get changed => lines.length != tx.items.length || lines.any((l) => l.itemId == null || l.qty != l.oldQty);
  bool get canRemove => lines.length > 1;

  List<String> get stockNotes =>
      stockChanges(tx.items, lines, {for (final p in _products.items) p.id: p.stock}, {for (final p in _products.items) p.id: p.name});

  void _edited() {
    _uuid = null; // a different edit is a different Simpan
    rowErrors.clear();
    error = null;
    notifyListeners();
  }

  void setQty(int i, int q) {
    lines[i].qty = q < 1 ? 1 : q;
    _edited();
  }

  void remove(int i) {
    if (!canRemove) return;
    lines.removeAt(i);
    _edited();
  }

  void add(Product p) {
    final at = lines.indexWhere((l) => l.productId == p.id);
    if (at >= 0) {
      lines[at].qty++;
    } else {
      lines.add(EditLine(productId: p.id, name: p.name, unitPrice: p.price, oldQty: 0, qty: 1));
    }
    _edited();
  }

  List<ReviseLine> get body => [
    for (final l in lines) l.itemId != null ? ReviseLine.keep(l.itemId!, l.qty) : ReviseLine.add(l.productId!, l.qty),
  ];

  /// The new version, or null when it failed (see [error] and [rowErrors]).
  Future<Transaction?> save() async {
    if (running || !changed) return null;
    _uuid ??= const Uuid().v7();
    running = true;
    error = null;
    rowErrors.clear();
    notifyListeners();
    try {
      final t = await _repo.revise(tx.id, clientUuid: _uuid!, lines: body);
      running = false;
      notifyListeners();
      return t;
    } on ApiException catch (e) {
      if (e.code == 'lines_invalid') {
        for (final l in (e.details?['lines'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          rowErrors[(l['line_no'] as int) - 1] = l['message'] as String;
        }
      }
      error = e.code == 'lines_invalid' ? 'Periksa barang yang bertanda.' : e.message;
    } on NetworkException catch (e) {
      error = messageOf(e);
    }
    running = false;
    notifyListeners();
    return null;
  }
}
