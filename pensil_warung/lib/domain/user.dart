class User {
  const User({
    required this.id,
    required this.displayName,
    required this.username,
    required this.email,
    required this.role,
    required this.permissions,
    required this.hasPassword,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        displayName: j['display_name'] as String,
        username: j['username'] as String,
        email: j['email'] as String,
        role: j['role'] as String,
        permissions: List<String>.from(j['permissions'] as List),
        hasPassword: j['has_password'] as bool,
      );

  final String id;
  final String displayName;
  final String username;
  final String email;
  final String role;
  final List<String> permissions;
  final bool hasPassword;

  bool get isBroadcaster => role == 'broadcaster';
}
