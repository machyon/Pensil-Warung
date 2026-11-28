import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/product_repository.dart';
import '../../domain/product.dart';

class ProductListViewModel extends ChangeNotifier {
  ProductListViewModel(this._repo) {
    _repo.addListener(notifyListeners);
    load();
  }

  final ProductRepository _repo;

  String query = '';
  String? error;
  bool loading = false;

  bool get loaded => _repo.loaded;
  int get total => _repo.items.length;

  /// Search filters the cached list; no request per key.
  List<Product> get shown => filterProducts(_repo.items, query);

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _repo.load();
    } catch (e) {
      // Keep a cached list on screen; only show the error when there is none.
      if (!_repo.loaded) error = messageOf(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _repo.removeListener(notifyListeners);
    super.dispose();
  }
}
