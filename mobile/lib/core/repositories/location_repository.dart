
import 'package:dio/dio.dart';
import '../models/live_location.dart';
import '../network/api_client.dart';

class LocationRepository {
  final Dio _dio = ApiClient().dio;

  Future<List<LiveLocation>> getAmbulances() => _list('/api/locations/ambulances');
  Future<List<LiveLocation>> getPolice() => _list('/api/locations/police');

  Future<List<LiveLocation>> _list(String path) async {
    final res = await _dio.get(path);
    return (res.data as List<dynamic>)
        .map((e) => LiveLocation.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
