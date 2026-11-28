import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config.dart';
import '../../data/api_exception.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/session.dart';

class LandingViewModel extends ChangeNotifier {
  LandingViewModel(this._auth, this._session);

  final AuthRepository _auth;
  final Session _session;

  bool running = false;
  String? error;
  static Future<void>? _init;

  Future<void> signInWithGoogle() async {
    if (running) return;
    running = true;
    error = null;
    notifyListeners();
    try {
      _init ??= GoogleSignIn.instance.initialize(serverClientId: googleServerClientId);
      await _init;
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw StateError('no id_token');
      final r = await _auth.google(idToken);
      await _session.signIn(r.token, r.user); // the router leaves Landing
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled &&
          e.code != GoogleSignInExceptionCode.interrupted) {
        dev.log('google sign-in failed: ${e.code.name}', name: 'auth');
        error = 'Gagal masuk dengan Google. Coba lagi.';
      }
    } on ApiException catch (e) {
      error = e.code == 'email_registered' ? e.message : 'Gagal masuk dengan Google. Coba lagi.';
    } on NetworkException {
      error = 'Tidak ada koneksi. Coba lagi.';
    } catch (e) {
      dev.log('google sign-in failed: ${e.runtimeType}', name: 'auth');
      error = 'Gagal masuk dengan Google. Coba lagi.';
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
