import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/session.dart';

class RegisterViewModel extends ChangeNotifier {
  RegisterViewModel(this._auth, this._session);

  final AuthRepository _auth;
  final Session _session;

  bool running = false;

  /// Error text by field: `display_name`, `email`, `password`, or `form`.
  final Map<String, String> errors = {};

  void edited(String field) {
    if (errors.remove(field) != null || errors.remove('form') != null) notifyListeners();
  }

  /// The same checks as the API, so an obvious mistake never costs a request.
  static Map<String, String> validate(String name, String email, String password) => {
        if (name.trim().isEmpty) 'display_name': 'Nama tidak boleh kosong.',
        if (email.trim().isEmpty) 'email': 'Email tidak boleh kosong.',
        if (password.length < 8 || password.length > 128) 'password': 'Password harus 8 sampai 128 karakter.',
      };

  Future<void> register(String name, String email, String password) async {
    if (running) return;
    errors
      ..clear()
      ..addAll(validate(name, email, password));
    if (errors.isNotEmpty) return notifyListeners();
    running = true;
    notifyListeners();
    try {
      final r = await _auth.register(name.trim(), email.trim(), password);
      await _session.signIn(r.token, r.user);
    } on ApiException catch (e) {
      final field = e.code == 'email_taken' ? 'email' : e.details?['field'];
      errors[field is String && const {'display_name', 'email', 'password'}.contains(field) ? field : 'form'] =
          e.message;
    } on NetworkException {
      errors['form'] = 'Tidak ada koneksi. Coba lagi.';
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
