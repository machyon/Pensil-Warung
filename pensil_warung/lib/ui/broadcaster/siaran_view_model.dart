import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/broadcaster_repository.dart';
import '../../domain/broadcast.dart';

/// The broadcaster's Siaran list. App-wide, so Tulis can show the recipient count and every save can refresh it.
class SiaranViewModel extends ChangeNotifier {
  SiaranViewModel(this._repo);

  final BroadcasterRepository _repo;

  int recipientCount = 0;
  List<Broadcast> scheduled = const [];
  List<Broadcast> sent = const [];
  String? nextCursor;
  bool loaded = false;
  bool loading = false;
  bool loadingMore = false;
  Object? error;

  /// First page. Keeps what is on screen while it reloads.
  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final p = await _repo.list();
      recipientCount = p.recipientCount;
      scheduled = p.scheduled;
      sent = p.sent;
      nextCursor = p.nextCursor;
      loaded = true;
    } on ApiException catch (e) {
      error = e;
    } on NetworkException catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (loadingMore || nextCursor == null) return;
    loadingMore = true;
    notifyListeners();
    try {
      final p = await _repo.list(cursor: nextCursor);
      sent = [...sent, ...p.sent];
      nextCursor = p.nextCursor;
    } on ApiException catch (e) {
      error = e;
    } on NetworkException catch (e) {
      error = e;
    }
    loadingMore = false;
    notifyListeners();
  }

  void clear() {
    recipientCount = 0;
    scheduled = sent = const [];
    nextCursor = null;
    loaded = false;
    error = null;
    notifyListeners();
  }
}
