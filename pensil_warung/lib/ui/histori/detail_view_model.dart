import 'package:flutter/foundation.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction.dart';

class DetailViewModel extends ChangeNotifier {
  DetailViewModel(this._repo, this.id) {
    load();
  }

  final TransactionRepository _repo;
  final int id;

  Transaction? tx;
  bool loading = true;
  Object? error;
  bool _disposed = false;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      tx = await _repo.get(id);
    } catch (e) {
      error = e;
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
