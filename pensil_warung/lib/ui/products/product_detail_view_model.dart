import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/product.dart';

class ProductDetailViewModel extends ChangeNotifier {
  ProductDetailViewModel(this._repo, this.id, this.product) {
    load();
  }

  final ProductRepository _repo;
  final int id;

  /// The cached row at first, then the fresh `GET /products/{id}`.
  Product? product;
  String? error;
  bool loading = true;

  /// This month's figures; null until known or when the request failed.
  int? sold;
  int? revenue;
  int? rank;

  final movements = <StockMovement>[];
  String? _next;
  bool loadingMore = false;

  bool get hasMore => _next != null;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await _repo.movements(id);
      product = await _repo.get(id);
      movements
        ..clear()
        ..addAll(page.items);
      _next = page.next;
    } catch (e) {
      error = messageOf(e);
    }
    loading = false;
    notifyListeners();
    // The month figures are secondary: a failure just leaves them blank.
    try {
      final items = await _repo.monthItems();
      final i = items.indexWhere((x) => x.productId == id);
      sold = i < 0 ? 0 : items[i].qty;
      revenue = i < 0 ? 0 : items[i].revenue;
      rank = i < 0 ? null : i + 1;
      notifyListeners();
    } catch (_) {}
  }

  /// Fresh product only (after a photo change).
  Future<void> refreshProduct() async {
    try {
      product = await _repo.get(id);
      notifyListeners();
    } catch (_) {}
  }

  bool _photoRetried = false;

  /// The photo URL failed to load (expired): refresh the product once.
  void photoFailed() {
    if (_photoRetried) return;
    _photoRetried = true;
    refreshProduct();
  }

  bool get photoPending => _repo.pendingPhotos.containsKey(id);

  bool retrying = false;

  Future<void> retryPhoto() async {
    final bytes = _repo.pendingPhotos[id];
    if (bytes == null || retrying) return;
    retrying = true;
    notifyListeners();
    await _repo.uploadPending(id, bytes);
    retrying = false;
    await refreshProduct();
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_next == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await _repo.movements(id, cursor: _next);
      movements.addAll(page.items);
      _next = page.next;
    } catch (_) {
      // Leave _next so the next scroll retries.
    }
    loadingMore = false;
    notifyListeners();
  }
}
