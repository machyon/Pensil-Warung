import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/user.dart';

/// The signed-in token and user. The token survives restarts in secure storage;
/// the user is loaded from `GET /me` by the splash.
class Session extends ChangeNotifier {
  Session({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'token';
  final FlutterSecureStorage _storage;

  String? _token;
  User? _user;

  String? get token => _token;
  User? get user => _user;
  bool get signedIn => _token != null && _user != null;

  /// Read the stored token (if any). The user stays null until [replaceToken]/[signIn].
  Future<void> restore() async {
    _token = await _storage.read(key: _key);
  }

  Future<void> signIn(String token, User user) async {
    _token = token;
    _user = user;
    await _storage.write(key: _key, value: token);
    notifyListeners();
  }

  /// Same as [signIn]; used when an endpoint returns a fresh token (email change).
  Future<void> replaceToken(String token, User user) => signIn(token, user);

  /// Set the user for the stored token, after `GET /me`.
  void setUser(User user) {
    _user = user;
    notifyListeners();
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    await _storage.delete(key: _key);
    notifyListeners();
  }
}
