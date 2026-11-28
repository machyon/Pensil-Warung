import 'package:flutter/foundation.dart';

import '../../data/prefs.dart';
import '../../data/repositories/broadcast_repository.dart';
import '../../domain/broadcast.dart';
import '../../data/api_exception.dart';

/// The broadcast feed plus which items were read (kept on the phone). App-wide, so every tab's bell can show the dot.
class NotificationFeed extends ChangeNotifier {
  NotificationFeed(this._repo, this._prefs) : _read = _prefs.readBroadcastIds;

  final BroadcastRepository _repo;
  final Prefs _prefs;
  final Set<int> _read;

  List<Broadcast> items = const [];
  bool loaded = false;
  bool loading = false;
  Object? error;

  bool isUnread(Broadcast b) => !_read.contains(b.id);
  int get unreadCount => items.where(isUnread).length;
  bool get hasUnread => unreadCount > 0;
  List<Broadcast> get unread => items.where(isUnread).toList();

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      items = await _repo.list();
      loaded = true;
    } on ApiException catch (e) {
      error = e;
    } on NetworkException catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> markRead(int id) async {
    if (!_read.add(id)) return;
    notifyListeners();
    await _prefs.addReadBroadcast(id);
  }

  /// The body for the sheet; fetched only when the broadcast has one.
  Future<String?> body(Broadcast b) async => b.hasBody ? (await _repo.detail(b.id)).body : null;

  void clear() {
    items = const [];
    loaded = false;
    error = null;
    notifyListeners();
  }
}
