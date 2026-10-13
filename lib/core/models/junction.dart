class Junction {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  const Junction({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory Junction.fromJson(Map<String, dynamic> json) => Junction(
    id: json['id'] as String,
    name: json['name'] as String,
    // JSON numbers can arrive as int or double.
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
  );
}