import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';
import '../network/token_storage.dart';
import '../models/app_user.dart';

class AuthService extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  final TokenStorage _tokenStorage = TokenStorage();

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  String _mapRole(String displayRole) {
    switch (displayRole) {
      case 'Ambulance Driver':
        return 'AMBULANCE_DRIVER';
      case 'Traffic Police':
        return 'POLICE';
      default:
        throw ArgumentError('Unknown role: $displayRole');
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final response = await _apiClient.dio.post('/api/auth/login', data: {
        'email': email,
        'password': password,
      });

      final token = response.data['token'] as String;
      await _tokenStorage.saveToken(token);
      await _fetchCurrentUser();
    } on DioException catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    try {
      await _apiClient.dio.post('/api/users/signup', data: {
        'email': email,
        'password': password,
        'fullName': fullName,
        'role': _mapRole(role),
      });
    } on DioException catch (e) {
      throw Exception(_friendlyError(e));
    }
  }

  Future<void> _fetchCurrentUser() async {
    final response = await _apiClient.dio.get('/api/users/me');
    _currentUser = AppUser.fromJson(response.data);
    notifyListeners();
  }

  Future<void> tryAutoLogin() async {
    final token = await _tokenStorage.getToken();
    if (token == null) return;
    try {
      await _fetchCurrentUser();
    } catch (_) {
      await _tokenStorage.clearToken();
    }
  }

  Future<void> signOut() async {
    await _tokenStorage.clearToken();
    _currentUser = null;
    notifyListeners();
  }

  String _friendlyError(DioException e) {
    if (e.response?.statusCode == 401) {
      return 'Invalid email or password.';
    }
    if (e.response?.statusCode == 409) {
      return 'This email is already registered.';
    }
    if (e.response?.statusCode == 400) {
      return 'Please check your details and try again.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Check your internet connection.';
    }
    return 'Something went wrong. Please try again.';
  }
}