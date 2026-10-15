import 'package:dio/dio.dart';
import '../models/police_assignment.dart';
import '../network/api_client.dart';

class PoliceRepository {
  final Dio _dio = ApiClient().dio;

  Future<PoliceAssignment> assign(String junctionId) async {
    final res = await _dio.put(
      '/api/police/assignment',
      data: {'junctionId': junctionId},
    );
    return PoliceAssignment.fromJson(res.data);
  }

  Future<List<PoliceAssignment>> getAssignments() async {
    final res = await _dio.get('/api/police/assignments');
    return (res.data as List<dynamic>)
        .map((e) => PoliceAssignment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}