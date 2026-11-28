import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/broadcaster_repository.dart';
import '../../domain/broadcast.dart';
import 'siaran_view_model.dart';

/// One broadcaster detail ([21] / [22]): load it, cancel it.
class BroadcastDetailViewModel extends ChangeNotifier {
  BroadcastDetailViewModel(this._repo, this._list, this.id);

  final BroadcasterRepository _repo;
  final SiaranViewModel _list;
  final int id;

  Broadcast? item;
  Object? error;
  bool running = false;

  Future<void> load() async {
    error = null;
    notifyListeners();
    try {
      item = await _repo.detail(id);
    } on ApiException catch (e) {
      error = e;
    } on NetworkException catch (e) {
      error = e;
    }
    notifyListeners();
  }

  /// True when cancelled. On `409 not_editable` the detail is reloaded so the screen shows its real status.
  Future<bool> cancel() async {
    if (running) return false;
    running = true;
    notifyListeners();
    try {
      item = await _repo.cancel(id);
      _list.load();
      running = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      error = e;
      if (e.code == 'not_editable') {
        running = false;
        await load();
        _list.load();
        error = e;
        notifyListeners();
        return false;
      }
    } on NetworkException catch (e) {
      error = e;
    }
    running = false;
    notifyListeners();
    return false;
  }
}
