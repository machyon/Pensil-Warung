import 'package:flutter/widgets.dart';

import '../../data/prefs.dart';

/// Tampilan: text size (applied to the whole app) and tema (saved, no effect yet).
class DisplaySettings extends ChangeNotifier {
  DisplaySettings(this._prefs) : textSize = _prefs.textSize, tema = _prefs.tema;

  final Prefs _prefs;

  static const textSizeLabels = ['Kecil', 'Sedang', 'Besar'];
  static const temaLabels = ['Terang', 'Gelap', 'Ikuti HP'];
  static const _scales = [0.9, 1.0, 1.2];

  int textSize;
  int tema;

  TextScaler get textScaler => TextScaler.linear(_scales[textSize]);

  void setTextSize(int v) {
    textSize = v;
    _prefs.setTextSize(v);
    notifyListeners();
  }

  void setTema(int v) {
    tema = v;
    _prefs.setTema(v);
    notifyListeners();
  }
}
