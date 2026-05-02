class AuthSession {
  const AuthSession({
    this.email,
    this.jwt,
    this.sessionToken,
    this.role,
    this.loyaltyPoints = 0,
  });

  final String? email;
  final String? jwt;
  final String? sessionToken;
  final String? role;
  final int loyaltyPoints;

  bool get isAdmin => role == 'admin';
  bool get isEmployee => role == 'employee';
  bool get isUser => role == null || role == 'user';

  bool get hasIdentity =>
      (sessionToken != null && sessionToken!.isNotEmpty) ||
      (email != null && email!.isNotEmpty);

  AuthSession copyWith({
    String? email,
    String? jwt,
    String? sessionToken,
    String? role,
    int? loyaltyPoints,
  }) {
    return AuthSession(
      email: email ?? this.email,
      jwt: jwt ?? this.jwt,
      sessionToken: sessionToken ?? this.sessionToken,
      role: role ?? this.role,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
    );
  }

  Map<String, dynamic> toRouteArgs() => {
        'email': email,
        'jwt': jwt,
        'sessionToken': sessionToken,
        'role': role,
        'loyaltyPoints': loyaltyPoints,
      };

  factory AuthSession.fromRouteArgs(Object? args) {
    if (args is Map) {
      return AuthSession(
        email: args['email']?.toString(),
        jwt: args['jwt']?.toString(),
        sessionToken: args['sessionToken']?.toString(),
        role: args['role']?.toString(),
        loyaltyPoints: _asInt(args['loyaltyPoints']) ?? 0,
      );
    }

    return const AuthSession();
  }
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
