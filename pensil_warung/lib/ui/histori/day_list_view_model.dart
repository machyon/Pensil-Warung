import 'package:flutter/foundation.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction.dart';

class DayListViewModel extends ChangeNotifier {
  DayListViewModel(this._repo, this.date) {
    _repo.addListener(load);
    load();
  }

  final TransactionRepository _repo;
  final String date;

  List<TxRow> rows = const [];
  DaySummary? day;
  String? _next;
  bool loading = true, loadingMore = false;
  Object? error;
  bool _disposed = false;

  bool get hasMore => _next != null;

  /// First page again (also after a void or revise elsewhere).
  Future<void> load() async {
    if (_disposed) return;
    if (rows.isEmpty) {
      loading = true;
      notifyListeners();
    }
    try {
      final p = await _repo.day(date);
      rows = p.rows;
      day = p.day;
      _next = p.next;
      error = null;
    } catch (e) {
      error = e;
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> loadMore() async {
    final c = _next;
    if (c == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final p = await _repo.day(date, cursor: c);
      rows = [...rows, ...p.rows];
      _next = p.next;
    } catch (_) {
      // keep the cursor: the next scroll tries again
    }
    loadingMore = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _repo.removeListener(load);
    super.dispose();
  }
}
