import 'package:shared_preferences/shared_preferences.dart';

/// Small settings kept on the phone. Today: which broadcasts were read.
class Prefs {
  Prefs(this._p);

  final SharedPreferences _p;

  static const _readKey = 'read_broadcast_ids';

  Set<int> get readBroadcastIds => {for (final s in _p.getStringList(_readKey) ?? const <String>[]) ?int.tryParse(s)};

  Future<void> addReadBroadcast(int id) =>
      _p.setStringList(_readKey, [for (final i in {...readBroadcastIds, id}) '$i']);
}
