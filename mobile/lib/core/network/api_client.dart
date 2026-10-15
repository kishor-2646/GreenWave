import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'token_storage.dart';

class ApiClient {
  // Created once, the first time ApiClient() is called.
  static final ApiClient _instance = ApiClient._internal();

  // Every ApiClient() call returns the same instance.
  factory ApiClient() => _instance;

  final Dio dio;
  final TokenStorage _tokenStorage = TokenStorage();

  ApiClient._internal()
      : dio = Dio(BaseOptions(
    baseUrl: dotenv.env['API_BASE_URL'] ?? '',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  )) {
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