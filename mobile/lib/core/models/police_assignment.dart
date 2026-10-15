class PoliceAssignment {
  final String userId;
  final String officerName;
  final String junctionId;
  final String junctionName;
  final double latitude;
  final double longitude;

  const PoliceAssignment({
    required this.userId,
    required this.officerName,
    required this.junctionId,
    required this.junctionName,
    required this.latitude,
    required this.longitude,
  });

  factory PoliceAssignment.fromJson(Map<String, dynamic> json) =>
      PoliceAssignment(
        userId: json['userId'] as String,
        officerName: json['officerName'] as String,
        junctionId: json['junctionId'] as String,
        junctionName: json['junctionName'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
}
