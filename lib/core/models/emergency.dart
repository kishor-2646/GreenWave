class ClearedJunction {
  final String junctionId;
  final String junctionName;
  final double latitude;
  final double longitude;
  final String clearedByUserId;
  final DateTime clearedAt;

  const ClearedJunction({
    required this.junctionId,
    required this.junctionName,
    required this.latitude,
    required this.longitude,
    required this.clearedByUserId,
    required this.clearedAt,
  });

  factory ClearedJunction.fromJson(Map<String, dynamic> json) =>
      ClearedJunction(
        junctionId: json['junctionId'] as String,
        junctionName: json['junctionName'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        clearedByUserId: json['clearedByUserId'] as String,
        clearedAt: DateTime.parse(json['clearedAt'] as String),
      );
}

class Emergency {
  final String id;
  final String ambulanceUserId;
  final String ambulanceName;
  final int criticality;
  final String status;
  final double destinationLat;
  final double destinationLng;
  final String? encodedPolyline;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<ClearedJunction> clearedJunctions;

  const Emergency({
    required this.id,
    required this.ambulanceUserId,
    required this.ambulanceName,
    required this.criticality,
    required this.status,
    required this.destinationLat,
    required this.destinationLng,
    required this.encodedPolyline,
    required this.startedAt,
    required this.endedAt,
    required this.clearedJunctions,
  });

  bool get isActive => status == 'ACTIVE';

  factory Emergency.fromJson(Map<String, dynamic> json) => Emergency(
    id: json['id'] as String,
    ambulanceUserId: json['ambulanceUserId'] as String,
    ambulanceName: json['ambulanceName'] as String,
    criticality: json['criticality'] as int,
    status: json['status'] as String,
    destinationLat: (json['destinationLat'] as num).toDouble(),
    destinationLng: (json['destinationLng'] as num).toDouble(),
    encodedPolyline: json['encodedPolyline'] as String?,
    startedAt: DateTime.parse(json['startedAt'] as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt'] as String),
    clearedJunctions: ((json['clearedJunctions'] as List<dynamic>?) ?? [])
        .map((e) => ClearedJunction.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// What arrives on /topic/emergencies: { type, emergency }.
class EmergencyEvent {
  final String type;
  final Emergency emergency;

  const EmergencyEvent({
    required this.type,
    required this.emergency,
  });

  factory EmergencyEvent.fromJson(Map<String, dynamic> json) =>
      EmergencyEvent(
        type: json['type'] as String,
        emergency: Emergency.fromJson(
          json['emergency'] as Map<String, dynamic>,
        ),
      );
}