import 'package:dio/dio.dart';
import '../models/emergency.dart';
import '../network/api_client.dart';

class EmergencyRepository {
  final Dio _dio = ApiClient().dio;

  Future<Emergency> start({
    required int criticality,
    required double destinationLat,
    required double destinationLng,
    String? encodedPolyline,
  }) async {
    final res = await _dio.post('/api/emergencies', data: {
      'criticality': criticality,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'encodedPolyline': encodedPolyline,
    });
    return Emergency.fromJson(res.data);
  }

  Future<Emergency> end(String id) async {
    final res = await _dio.post('/api/emergencies/$id/end');
    return Emergency.fromJson(res.data);
  }

  /// The backend answers 204 (no body) when this driver has no active emergency.
  Future<Emergency?> getMine() async {
    final res = await _dio.get('/api/emergencies/active/mine');
    if (res.statusCode == 204 || res.data == null || res.data == '') {
      return null;
    }
    return Emergency.fromJson(res.data);
  }

  Future<List<Emergency>> getActive() async {
    final res = await _dio.get('/api/emergencies/active');
    return (res.data as List<dynamic>)
        .map((e) => Emergency.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Emergency>> getHistory() async {
    final res = await _dio.get('/api/emergencies');
    return (res.data as List<dynamic>)
        .map((e) => Emergency.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Emergency> markCleared(String emergencyId, String junctionId) async {
    final res = await _dio.put(
      '/api/emergencies/$emergencyId/clearances/$junctionId',
    );
    return Emergency.fromJson(res.data);
  }

  Future<Emergency> revertClearance(
      String emergencyId,
      String junctionId,
      ) async {
    final res = await _dio.delete(
      '/api/emergencies/$emergencyId/clearances/$junctionId',
    );
    return Emergency.fromJson(res.data);
  }
}