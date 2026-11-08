class RealNumberRegisterResult {
  final String username;
  final String userId;
  final String secret;

  RealNumberRegisterResult({
    required this.username,
    required this.userId,
    required this.secret,
  });

  factory RealNumberRegisterResult.fromJson(Map<String, dynamic> json) {
    return RealNumberRegisterResult(
      username: json['username'],
      userId: json['userid'],
      secret: json['secret'],
    );
  }
}
