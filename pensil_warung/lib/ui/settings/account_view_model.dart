import 'package:flutter/foundation.dart';

import '../../data/api_exception.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/session.dart';

/// Shared state of the account forms: one request at a time, errors mapped for the screen.
abstract class FormModel extends ChangeNotifier {
  bool running = false;
  bool _dead = false;

  /// An error not tied to one field.
  String? error;

  /// Handle a field-level [ApiException]; return false to show its message as [error].
  bool onApi(ApiException e) => false;

  Future<bool> run(Future<void> Function() body) async {
    if (running) return false;
    running = true;
    error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on ApiException catch (e) {
      if (!onApi(e)) error = e.message;
    } on NetworkException {
      error = 'Tidak ada koneksi. Coba lagi.';
    } finally {
      running = false;
      notifyListeners();
    }
    return false;
  }

  @override
  void notifyListeners() {
    if (!_dead) super.notifyListeners(); // a sign-out can dispose the screen mid-request
  }

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }
}

class UsernameViewModel extends FormModel {
  UsernameViewModel(this._repo, this._session);

  final AccountRepository _repo;
  final Session _session;

  static final valid = RegExp(r'^[a-z0-9_]{3,30}$');

  String? usernameError;

  void edited() {
    if (usernameError == null && error == null) return;
    usernameError = null;
    error = null;
    notifyListeners();
  }

  Future<bool> save(String username) => run(() async {
        usernameError = null;
        _session.setUser(await _repo.changeUsername(username));
      });

  @override
  bool onApi(ApiException e) {
    if (e.code == 'username_taken') {
      usernameError = 'Username sudah dipakai';
    } else if (e.code == 'invalid_value') {
      usernameError = e.message;
    } else {
      return false;
    }
    return true;
  }
}

/// Email and password changes both answer with a fresh token, which replaces the old one.
class EmailViewModel extends FormModel {
  EmailViewModel(this._repo, this._session);

  final AccountRepository _repo;
  final Session _session;

  static final valid = RegExp(r'^\S+@\S+\.\S+$');

  String? emailError;
  String? passwordError;

  void edited() {
    if (emailError == null && passwordError == null && error == null) return;
    emailError = passwordError = error = null;
    notifyListeners();
  }

  Future<bool> save(String email, String password) => run(() async {
        emailError = passwordError = null;
        final r = await _repo.changeEmail(email, password);
        await _session.replaceToken(r.token, r.user);
      });

  @override
  bool onApi(ApiException e) {
    switch (e.code) {
      case 'invalid_credentials':
        passwordError = 'Kata sandi salah';
      case 'email_taken' || 'invalid_value':
        emailError = e.message;
      default:
        return false;
    }
    return true;
  }
}

class PasswordViewModel extends FormModel {
  PasswordViewModel(this._repo, this._session);

  final AccountRepository _repo;
  final Session _session;

  String? currentError;
  String? newError;

  void edited() {
    if (currentError == null && newError == null && error == null) return;
    currentError = newError = error = null;
    notifyListeners();
  }

  Future<bool> save(String current, String next) => run(() async {
        currentError = newError = null;
        final r = await _repo.changePassword(current, next);
        await _session.replaceToken(r.token, r.user);
      });

  @override
  bool onApi(ApiException e) {
    switch (e.code) {
      case 'invalid_credentials':
        currentError = 'Kata sandi salah';
      case 'invalid_value':
        newError = e.message;
      default:
        return false;
    }
    return true;
  }
}
