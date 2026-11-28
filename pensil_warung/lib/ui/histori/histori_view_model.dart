import 'package:flutter/foundation.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/analytics.dart';
import '../core/format.dart';

/// `2026-11` -> 2026 * 12 + 10, so months can be compared and stepped.
int monthIndex(String m) => int.parse(m.substring(0, 4)) * 12 + int.parse(m.substring(5, 7)) - 1;
String monthKey(int i) => '${i ~/ 12}-${two(i % 12 + 1)}';

class HistoriViewModel extends ChangeNotifier {
  HistoriViewModel(this._repo, this._tx) {
    _tx.addListener(load);
    load();
  }

  final AnalyticsRepository _repo;
  final TransactionRepository _tx;

  bool loading = true;
  Object? error;
  List<MonthTotal> months = const [];
  late String month = currentMonth;
  MonthSummary? summary;
  List<DayTotal> days = const [];
  bool showAll = false;

  String? expanded;
  final dayItems = <String, DayItems>{};
  Object? dayError;

  static String get currentMonth {
    final w = wib(DateTime.now());
    return '${w.year}-${two(w.month)}';
  }

  static String get today => wibIsoDate(DateTime.now());

  bool get isEmpty => !loading && error == null && months.isEmpty;

  /// First month with sales, to the current month.
  String get firstMonth => months.isEmpty ? currentMonth : months.last.month;
  bool get canPrev => monthIndex(month) > monthIndex(firstMonth);
  bool get canNext => monthIndex(month) < monthIndex(currentMonth);

  Future<void> load() async {
    if (_disposed) return;
    final first = summary == null;
    if (first) {
      loading = true;
      notifyListeners();
    }
    try {
      months = await _repo.months();
      if (months.isNotEmpty) {
        final r = await Future.wait([_repo.month(month), _repo.days(month)]);
        summary = r[0] as MonthSummary;
        days = r[1] as List<DayTotal>;
      }
      error = null;
      dayItems.clear();
      if (expanded != null) _loadItems(expanded!);
    } catch (e) {
      error = e;
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> setMonth(String m) async {
    if (m == month) return;
    month = m;
    expanded = null;
    showAll = false;
    summary = null;
    days = const [];
    dayItems.clear();
    await load();
  }

  void step(int delta) => setMonth(monthKey(monthIndex(month) + delta));

  void toggle(String day) {
    expanded = expanded == day ? null : day;
    notifyListeners();
    if (expanded != null && !dayItems.containsKey(day)) _loadItems(day);
  }

  Future<void> _loadItems(String day) async {
    dayError = null;
    try {
      dayItems[day] = await _repo.dayItems(day);
    } catch (e) {
      dayError = e;
    }
    if (!_disposed) notifyListeners();
  }

  void retryItems() {
    final d = expanded;
    if (d != null) {
      dayError = null;
      notifyListeners();
      _loadItems(d);
    }
  }

  void expandList() {
    showAll = true;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _tx.removeListener(load);
    super.dispose();
  }
}

