class AuthResponse {
  final int id;
  final String accessToken;
  final String refreshToken;
  final String email;
  final String name;

  AuthResponse({
    required this.id,
    required this.accessToken,
    required this.refreshToken,
    required this.email,
    required this.name,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      id: json['id'] ?? json['userId'] ?? 0,
      accessToken: json['accessToken'] ?? json['token'] ?? json['jwt'] ?? '',
      refreshToken: json['refreshToken'] ?? json['refresh_token'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
    );
  }
}
