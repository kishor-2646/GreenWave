
class LiveLocation {
  final String userId;
  final String fullName;
  final String role;
  final double latitude;
  final double longitude;
  final double? heading;
  final DateTime updatedAt;

  const LiveLocation({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.updatedAt,
  });

  // Matches backend LocationBroadcast, /topic/ambulance-updates and /topic/police-updates
  factory LiveLocation.fromJson(Map<String, dynamic> json) => LiveLocation(
    userId: json['userId'] as String,
    fullName: json['fullName'] as String,
    role: json['role'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    heading: (json['heading'] as num?)?.toDouble(),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
