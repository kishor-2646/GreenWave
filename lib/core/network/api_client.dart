import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'token_storage.dart';

class ApiClient {
  final Dio dio;
  final TokenStorage _tokenStorage = TokenStorage();

  ApiClient() : dio = Dio(BaseOptions(baseUrl: dotenv.env['API_BASE_URL'] ?? '')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            await _tokenStorage.clearToken();
          }
          handler.next(error);
        },
      ),
    );
  }
}