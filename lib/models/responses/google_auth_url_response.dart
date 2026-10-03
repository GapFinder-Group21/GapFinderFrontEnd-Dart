class GoogleAuthUrlResponse {
  final String url;

  GoogleAuthUrlResponse({required this.url});

  factory GoogleAuthUrlResponse.fromJson(Map<String, dynamic> json) {
    return GoogleAuthUrlResponse(url: json['url'] as String);
  }
}
