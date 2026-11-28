import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../domain/analytics.dart';

/// Top 5 by share plus "Lainnya" (the rest, hidden when it rounds to 0).
List<({String label, double pct})> shareSegments(List<SoldItem> items) {
  final top = items.take(5).toList();
  final rest = 100 - top.fold<double>(0, (a, i) => a + i.sharePct);
  return [
    for (final i in top) (label: i.item.name, pct: i.sharePct),
    if (items.length > 5 && rest >= 0.05) (label: 'Lainnya', pct: double.parse(rest.toStringAsFixed(1))),
  ];
}

/// [09] Barang terjual: one month's items with a debounced name search.
class BarangViewModel extends ChangeNotifier {
  BarangViewModel(this._repo, this.month, {this._debounce = const Duration(milliseconds: 300)}) {
    load();
  }

  final AnalyticsRepository _repo;
  final String month;
  final Duration _debounce;

  bool loading = true;
  Object? error;
  MonthItems? data; // for the current query
  List<SoldItem> allItems = const []; // unfiltered, for the share bar
  String q = '';
  Timer? _timer;
  bool _disposed = false;

  List<({String label, double pct})> get segments => shareSegments(allItems);

  Future<void> load() async {
    final asked = q;
    loading = data == null;
    notifyListeners();
    try {
      final r = await _repo.monthItems(month, q: asked);
      if (_disposed || asked != q) return;
      data = r;
      if (asked.isEmpty) allItems = r.items;
      error = null;
    } catch (e) {
      if (_disposed || asked != q) return;
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  void search(String text) {
    q = text.trim();
    _timer?.cancel();
    _timer = Timer(_debounce, load);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
