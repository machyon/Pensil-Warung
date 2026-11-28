import '../../domain/user.dart';
import '../api_client.dart';
import 'auth_repository.dart';

/// `/me`: profile reads and changes. Email and password changes return a fresh token.
class AccountRepository {
  AccountRepository(this._api);

  final ApiClient _api;

  Future<User> me() async => User.fromJson(await _api.get('/api/v1/me') as Map<String, dynamic>);

  Future<User> changeUsername(String username) async =>
      User.fromJson(await _api.patch('/api/v1/me/username', body: {'username': username}) as Map<String, dynamic>);

  Future<AuthResult> changeEmail(String email, String currentPassword) async => _login(
      await _api.patch('/api/v1/me/email', body: {'email': email, 'current_password': currentPassword}));

  Future<AuthResult> changePassword(String currentPassword, String newPassword) async => _login(await _api
      .put('/api/v1/me/password', body: {'current_password': currentPassword, 'new_password': newPassword}));

  /// Password users send [password]; Google-only users send a fresh [idToken]. `204`.
  Future<void> deleteAccount({String? password, String? idToken}) => _api.delete('/api/v1/me',
      body: {'current_password': ?password, 'id_token': ?idToken});

  AuthResult _login(dynamic j) => (
        token: (j as Map<String, dynamic>)['token'] as String,
        user: User.fromJson(j['user'] as Map<String, dynamic>),
        created: false,
      );
}
