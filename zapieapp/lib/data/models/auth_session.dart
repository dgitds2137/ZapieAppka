class AuthSession {
  const AuthSession({
    this.email,
    this.jwt,
    this.sessionToken,
  });

  final String? email;
  final String? jwt;
  final String? sessionToken;

  bool get hasIdentity =>
      (sessionToken != null && sessionToken!.isNotEmpty) ||
      (email != null && email!.isNotEmpty);

  Map<String, dynamic> toRouteArgs() => {
        'email': email,
        'jwt': jwt,
        'sessionToken': sessionToken,
      };

  factory AuthSession.fromRouteArgs(Object? args) {
    if (args is Map) {
      return AuthSession(
        email: args['email']?.toString(),
        jwt: args['jwt']?.toString(),
        sessionToken: args['sessionToken']?.toString(),
      );
    }

    return const AuthSession();
  }
}
