import 'package:flutter/foundation.dart';

import '../../domain/product.dart';
import '../../ui/core/format.dart';
import '../api_client.dart';

/// Products API plus the last `GET /products` list ([items]), which other
/// screens (Catat's dictionary, photos) read.
class ProductRepository extends ChangeNotifier {
  ProductRepository(this._api);

  final ApiClient _api;

  List<Product> items = const [];
  bool loaded = false;

  /// Refresh the cache. Throws on failure and leaves the old list.
  Future<void> load() async {
    final j = await _api.get('/api/v1/products') as Map<String, dynamic>;
    items = [for (final p in j['items'] as List) Product.fromJson(p as Map<String, dynamic>)];
    loaded = true;
    notifyListeners();
  }

  /// After a save that succeeded: a failed refresh must not look like a failed save.
  Future<void> _refresh() async {
    try {
      await load();
    } catch (_) {}
  }

  /// Merge a save's `products_changed` / `products_deleted` into the cache. The answer has no
  /// photo, so an existing product keeps its own.
  void applyChanges(List<Product> changed, List<int> deleted) {
    final byId = {for (final p in items) p.id: p};
    for (final p in changed) {
      final old = byId[p.id];
      byId[p.id] = old == null || p.photoUrl != null
          ? p
          : Product(id: p.id, name: p.name, price: p.price, stock: p.stock, photoUrl: old.photoUrl);
    }
    deleted.forEach(byId.remove);
    items = byId.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
  }

  void clear() {
    items = const [];
    loaded = false;
    notifyListeners();
  }

  Future<Product> get(int id) async =>
      Product.fromJson(await _api.get('/api/v1/products/$id') as Map<String, dynamic>);

  Future<({List<StockMovement> items, String? next})> movements(int id, {String? cursor}) async {
    final j = await _api.get('/api/v1/products/$id/movements', query: {
      'limit': '20',
      'cursor': ?cursor,
    }) as Map<String, dynamic>;
    return (
      items: [for (final m in j['items'] as List) StockMovement.fromJson(m as Map<String, dynamic>)],
      next: j['next_cursor'] as String?,
    );
  }

  /// Sold items this WIB month, best seller first (the API's order).
  Future<List<MonthItem>> monthItems() async {
    final w = wib(DateTime.now());
    final j = await _api.get('/api/v1/analytics/month/items', query: {'month': '${w.year}-${two(w.month)}'})
        as Map<String, dynamic>;
    return [
      for (final i in j['items'] as List)
        MonthItem(
          productId: (i as Map<String, dynamic>)['product_id'] as int,
          qty: i['qty'] as int,
          revenue: i['revenue'] as int,
        ),
    ];
  }

  /// Returns the new products in request order.
  Future<List<Product>> bulkAdd(List<({String name, int price, int stock})> rows) async {
    final j = await _api.post('/api/v1/products/bulk', body: {
      'items': [for (final r in rows) {'name': r.name, 'price': r.price, 'stock': r.stock}],
    }) as Map<String, dynamic>;
    await _refresh();
    return [for (final p in j['items'] as List) Product.fromJson(p as Map<String, dynamic>)];
  }

  /// Photos picked for a product that did not exist yet and failed to upload,
  /// kept so Detail can offer "Coba lagi".
  final pendingPhotos = <int, Uint8List>{};
  final _photoRetried = <int>{};

  Future<Product> uploadPhoto(int id, Uint8List bytes) async {
    final p = Product.fromJson(await _api.multipart(
      '/api/v1/products/$id/photo',
      field: 'photo',
      bytes: bytes,
      filename: 'photo.jpg',
      method: 'PUT',
    ) as Map<String, dynamic>);
    pendingPhotos.remove(id);
    _photoRetried.remove(id);
    items = [for (final x in items) x.id == id ? p : x];
    notifyListeners();
    return p;
  }

  Future<void> deletePhoto(int id) async {
    await _api.delete('/api/v1/products/$id/photo');
    await _refresh();
  }

  /// Upload a photo chosen before the product was saved. On failure the bytes
  /// stay in [pendingPhotos] and this returns false.
  Future<bool> uploadPending(int id, Uint8List bytes) async {
    try {
      await uploadPhoto(id, bytes);
      return true;
    } catch (_) {
      pendingPhotos[id] = bytes;
      notifyListeners();
      return false;
    }
  }

  /// Presigned photo URLs expire: refresh the list once per product when one fails to load.
  void photoFailed(int id) {
    if (_photoRetried.add(id)) _refresh();
  }

  /// Only the fields passed are sent.
  Future<Product> update(int id, {String? name, int? price, int? stock}) async {
    final p = Product.fromJson(await _api.patch('/api/v1/products/$id', body: {
      'name': ?name,
      'price': ?price,
      'stock': ?stock,
    }) as Map<String, dynamic>);
    await _refresh();
    return p;
  }

  Future<void> delete(int id) async {
    await _api.delete('/api/v1/products/$id');
    items = [for (final p in items) if (p.id != id) p];
    notifyListeners();
  }
}

/// Case-insensitive name filter used by the Produk search.
List<Product> filterProducts(List<Product> all, String q) {
  final s = q.trim().toLowerCase();
  return s.isEmpty ? all : [for (final p in all) if (p.name.toLowerCase().contains(s)) p];
}
