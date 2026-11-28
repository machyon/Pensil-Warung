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

  Future<void> bulkAdd(List<({String name, int price, int stock})> rows) async {
    await _api.post('/api/v1/products/bulk', body: {
      'items': [for (final r in rows) {'name': r.name, 'price': r.price, 'stock': r.stock}],
    });
    await _refresh();
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
