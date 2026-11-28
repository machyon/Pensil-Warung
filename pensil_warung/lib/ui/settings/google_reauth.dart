import 'package:google_sign_in/google_sign_in.dart';

import '../auth/google_sign_in_model.dart';

/// The Google side of settings: a fresh `id_token` for Hapus akun, and sign-out.
/// Tests replace it.
class GoogleReauth {
  const GoogleReauth();

  /// A fresh Google sign-in's `id_token`, or null when the user cancels.
  Future<String?> idToken() async {
    await GoogleSignInModel.ensureInitialized();
    try {
      return (await GoogleSignIn.instance.authenticate()).authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) return null;
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignInModel.ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {} // nothing to sign out of
  }
}
