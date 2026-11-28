import 'package:flutter/foundation.dart';

const _rawBaseUrl = String.fromEnvironment('API_BASE_URL');

/// API host, trailing slashes trimmed once here. Every request is this + a path
/// starting with `/api/v1` or `/health`.
final String apiBaseUrl = _rawBaseUrl.replaceAll(RegExp(r'/+$'), '');

/// Web client id, passed to google_sign_in as `serverClientId`.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Call once at startup.
void checkConfig() {
  if (apiBaseUrl.isEmpty) {
    if (kDebugMode) {
      throw StateError(
        'API_BASE_URL kosong. Jalankan dengan --dart-define-from-file=.env',
      );
    }
    throw StateError('API_BASE_URL is not set');
  }
  if (kReleaseMode && !apiBaseUrl.startsWith('https://')) {
    throw StateError('API_BASE_URL must be https:// in release builds');
  }
}
