import 'package:dio/dio.dart';

/// Turns any exception into a short sentence a driver can read.
/// Screens call this instead of showing technical Dio errors.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    switch (error.response?.statusCode) {
      case 400:
        return 'Please check your details and try again.';
      case 401:
        return 'Your session expired. Please sign in again.';
      case 403:
        return 'You are not allowed to do that.';
      case 404:
        return 'Not found. It may have been removed.';
      case 409:
        return 'That conflicts with the current state. Please refresh.';
    }

    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Check your internet connection.';
      default:
        break;
    }
  }

  return 'Something went wrong. Please try again.';
}