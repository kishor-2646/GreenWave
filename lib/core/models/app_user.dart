class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool isVerified;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isVerified,
  });

  String get uid => id;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'],
      email: json['email'],
      fullName: json['fullName'],
      role: json['role'],
      isVerified: json['isVerified'],
    );
  }
}