
import 'package:dio/dio.dart';
import '../models/app_user.dart';
import '../network/api_client.dart';

class UserRepository {
  final Dio _dio = ApiClient().dio;

  /// ADMIN only on the server. [role] is the backend enum name, e.g. AMBULANCE_DRIVER.
  Future<List<AppUser>> getByRole(String role) async {
    final res = await _dio.get(
      '/api/users',
      queryParameters: {'role': role},
    );

    return (res.data as List<dynamic>)
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
