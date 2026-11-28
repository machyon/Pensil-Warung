import 'package:shared_preferences/shared_preferences.dart';

/// Small settings kept on the phone. Which broadcasts were read, the text size and the saved tema.
class Prefs {
  Prefs(this._p);

  final SharedPreferences _p;

  static const _readKey = 'read_broadcast_ids';

  Set<int> get readBroadcastIds => {for (final s in _p.getStringList(_readKey) ?? const <String>[]) ?int.tryParse(s)};

  Future<void> addReadBroadcast(int id) =>
      _p.setStringList(_readKey, [for (final i in {...readBroadcastIds, id}) '$i']);

  /// Index into Kecil / Sedang / Besar; Sedang by default.
  int get textSize => _p.getInt('text_size') ?? 1;
  Future<void> setTextSize(int v) => _p.setInt('text_size', v);

  /// Index into Terang / Gelap / Ikuti HP. Saved only: the app stays light.
  int get tema => _p.getInt('tema') ?? 0;
  Future<void> setTema(int v) => _p.setInt('tema', v);
}
