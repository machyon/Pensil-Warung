import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/product.dart';
import '../core/money_input.dart';

class ProductEditViewModel extends ChangeNotifier {
  ProductEditViewModel(this._repo, this.product);

  final ProductRepository _repo;
  final Product product;

  bool running = false;
  String? nameError;
  late String? photoUrl = product.photoUrl;

  Future<void> refreshPhoto() async {
    try {
      photoUrl = (await _repo.get(product.id)).photoUrl;
      notifyListeners();
    } catch (_) {}
  }

  String? error;

  String name = '';
  String price = '';
  String stock = '';

  int? get newPrice => parseRupiah(price);

  /// "Semula Rp15.000..." shows only when the price differs.
  bool get priceChanged => newPrice != null && newPrice != product.price;

  void edited() {
    if (nameError == null && error == null) return;
    nameError = null;
    error = null;
    notifyListeners();
  }

  /// True when saved (or nothing to save).
  Future<bool> save() async {
    if (running) return false;
    final n = name.trim();
    final pr = newPrice, st = int.tryParse(stock);
    if (n.isEmpty) {
      nameError = 'Nama barang tidak boleh kosong.';
      notifyListeners();
      return false;
    }
    if (pr == null || st == null) {
      error = 'Harga dan stok harus diisi.';
      notifyListeners();
      return false;
    }
    final changed = n != product.name || pr != product.price || st != product.stock;
    if (!changed) return true;
    running = true;
    nameError = error = null;
    notifyListeners();
    try {
      await _repo.update(
        product.id,
        name: n != product.name ? n : null,
        price: pr != product.price ? pr : null,
        stock: st != product.stock ? st : null,
      );
      return true;
    } on ApiException catch (e) {
      if (e.code == 'name_taken' || e.code == 'invalid_name') {
        nameError = e.message;
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
}
