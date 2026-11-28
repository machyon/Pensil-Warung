import 'package:flutter/widgets.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/product_repository.dart';
import '../core/money_input.dart';

class BulkRow {
  BulkRow([String name = '']) : nameCtrl = TextEditingController(text: name);

  final TextEditingController nameCtrl;
  final priceCtrl = TextEditingController();
  final stockCtrl = TextEditingController();
  String? nameError;

  String get name => nameCtrl.text.trim();
  int? get price => parseRupiah(priceCtrl.text);
  bool get blank => name.isEmpty && priceCtrl.text.isEmpty && stockCtrl.text.isEmpty;

  /// Only a row with a name and a price is sent. A missing stock means 0.
  bool get ready => name.isNotEmpty && price != null;

  /// The reason a filled-in row is skipped, else null.
  String? get skipNote {
    if (blank || ready) return null;
    return name.isEmpty ? 'Belum ada nama, jadi belum ikut disimpan.' : 'Belum ada harga, jadi belum ikut disimpan.';
  }

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    stockCtrl.dispose();
  }
}

class BulkAddViewModel extends ChangeNotifier {
  BulkAddViewModel(this._repo, {String? firstName}) : rows = [BulkRow(firstName ?? '')];

  final ProductRepository _repo;
  final List<BulkRow> rows;

  bool running = false;
  String? error;

  int get readyCount => rows.where((r) => r.ready).length;

  void add() {
    rows.add(BulkRow());
    notifyListeners();
  }

  void remove(BulkRow r) {
    rows.remove(r);
    if (rows.isEmpty) rows.add(BulkRow());
    notifyListeners();
  }

  void edited(BulkRow r) {
    r.nameError = null;
    error = null;
    notifyListeners();
  }

  /// True when everything was saved.
  Future<bool> save() async {
    if (running || readyCount == 0) return false;
    final sent = rows.where((r) => r.ready).toList();
    running = true;
    error = null;
    for (final r in rows) {
      r.nameError = null;
    }
    notifyListeners();
    try {
      await _repo.bulkAdd([
        for (final r in sent) (name: r.name, price: r.price!, stock: int.tryParse(r.stockCtrl.text) ?? 0),
      ]);
      return true;
    } on ApiException catch (e) {
      final i = e.details?['index'];
      if (e.code == 'name_taken' && i is int && i >= 0 && i < sent.length) {
        sent[i].nameError = e.message;
      } else {
        error = e.message;
      }
      return false;
    } on NetworkException {
      error = messageOf(const NetworkException());
      return false;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }
}
