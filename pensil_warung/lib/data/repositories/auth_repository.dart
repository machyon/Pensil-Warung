import '../../domain/user.dart';
import '../api_client.dart';

/// Token + user from an auth endpoint. [created] is only set by `/auth/google`.
typedef AuthResult = ({String token, User user, bool created});

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// `POST /auth/google`: 200 existing user, 201 new user.
  Future<AuthResult> google(String idToken) async {
    final j = await _api.post('/api/v1/auth/google', body: {'id_token': idToken})
        as Map<String, dynamic>;
    return (
      token: j['token'] as String,
      user: User.fromJson(j['user'] as Map<String, dynamic>),
      created: j['created'] == true,
    );
  }
}
