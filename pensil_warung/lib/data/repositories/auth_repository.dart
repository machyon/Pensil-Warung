import '../../domain/user.dart';
import '../api_client.dart';

/// Token + user from an auth endpoint. [created] is only set by `/auth/google`.
typedef AuthResult = ({String token, User user, bool created});

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<AuthResult> login(String email, String password) =>
      _auth('/api/v1/auth/login', {'email': email, 'password': password});

  /// "Nama" is `display_name`.
  Future<AuthResult> register(String name, String email, String password) => _auth(
      '/api/v1/auth/register', {'display_name': name, 'email': email, 'password': password});

  Future<AuthResult> _auth(String path, Object body) async {
    final j = await _api.post(path, body: body) as Map<String, dynamic>;
    return (
      token: j['token'] as String,
      user: User.fromJson(j['user'] as Map<String, dynamic>),
      created: j['created'] == true,
    );
  }

  /// `POST /auth/google`: 200 existing user, 201 new user.
  Future<AuthResult> google(String idToken) => _auth('/api/v1/auth/google', {'id_token': idToken});
}
