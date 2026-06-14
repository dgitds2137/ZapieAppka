class SocialAuthStart {
  const SocialAuthStart({
    required this.provider,
    required this.authorizationUrl,
    required this.redirectUri,
    required this.state,
    this.nonce,
  });

  final String provider;
  final String authorizationUrl;
  final String redirectUri;
  final String state;
  final String? nonce;

  factory SocialAuthStart.fromJson(Map<String, dynamic> json) {
    return SocialAuthStart(
      provider: json['provider']?.toString() ?? '',
      authorizationUrl: json['authorization_url']?.toString() ?? '',
      redirectUri: json['redirect_uri']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      nonce: json['nonce']?.toString(),
    );
  }
}
