class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final bool isVerified;
  final String? mobile;
  final String? hospital;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isVerified,
    this.mobile,
    this.hospital,
  });

  String get uid => id;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'],
      email: json['email'],
      fullName: json['fullName'],
      role: json['role'],
      isVerified: json['isVerified'],
      mobile: json['mobile'] as String?,
      hospital: json['hospital'] as String?,
    );
  }
}