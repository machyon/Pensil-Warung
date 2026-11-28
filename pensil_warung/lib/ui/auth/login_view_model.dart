import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/session.dart';

class LoginViewModel extends ChangeNotifier {
  LoginViewModel(this._auth, this._session);

  final AuthRepository _auth;
  final Session _session;

  bool running = false;
  bool wrongPassword = false;
  String? error;

  /// Typing clears the red state.
  void edited() {
    if (!wrongPassword && error == null) return;
    wrongPassword = false;
    error = null;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    if (running) return;
    running = true;
    wrongPassword = false;
    error = null;
    notifyListeners();
    try {
      final r = await _auth.login(email.trim(), password);
      await _session.signIn(r.token, r.user);
    } on ApiException catch (e) {
      if (e.code == 'invalid_credentials') {
        wrongPassword = true;
      } else {
        error = e.message;
      }
    } on NetworkException {
      error = 'Tidak ada koneksi. Coba lagi.';
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
