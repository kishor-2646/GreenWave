import 'package:dio/dio.dart';
import '../models/junction.dart';
import '../network/api_client.dart';

class JunctionRepository {
  final Dio _dio = ApiClient().dio;

  Future<List<Junction>> getAll() async {
    final res = await _dio.get('/api/junctions');
    return (res.data as List<dynamic>)
        .map((e) => Junction.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}