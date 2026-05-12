import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_disposable.dart';
import 'package:get_storage/get_storage.dart';

import '../utils/AppState.dart';

class ApiService extends GetxService {
  late Dio _dio;
  final storage = GetStorage();

  static const String defaultUrl = "https://fujishkacloud.in/backend/";

  String get baseUrl {
    String url = AppState.serverUrl;
    if (url.isEmpty || !url.startsWith('http')) {
      return defaultUrl;
    }
    return url.endsWith('/') ? url : '$url/';
  }

  @override
  void onInit() {
    super.onInit();
    _initializeDio();
  }

  void _initializeDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 90),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.transformer = BackgroundTransformer();

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = baseUrl;
          options.headers['mobileapptoken'] = AppState.token;

          if (kDebugMode) {
            print('🚀 [API] REQUEST: ${options.method} ${options.baseUrl}${options.path}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            print('✅ [API] RESPONSE [${response.statusCode}]');
          }
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          _logError(e);
          // Don't show snackbar here automatically, let the UI/Caller decide
          return handler.next(e);
        },
      ),
    );
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> post(String path, {dynamic data}) async {
    try {
      return await _dio.post(path, data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> put(String path, {dynamic data}) async {
    try {
      return await _dio.put(path, data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> delete(String path) async {
    try {
      return await _dio.delete(path);
    } catch (e) {
      rethrow;
    }
  }

  void _logError(DioException error) {
    String errorDescription = "";
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        errorDescription = "Connection timeout";
        break;
      case DioExceptionType.sendTimeout:
        errorDescription = "Send timeout";
        break;
      case DioExceptionType.receiveTimeout:
        errorDescription = "Receive timeout";
        break;
      case DioExceptionType.badResponse:
        errorDescription = "Server Error: ${error.response?.statusCode}";
        break;
      case DioExceptionType.cancel:
        errorDescription = "Request cancelled";
        break;
      case DioExceptionType.connectionError:
        errorDescription = "No Internet Connection";
        break;
      default:
        errorDescription = "Network error occurred";
    }

    if (kDebugMode) {
      print('❌ API ERROR: $errorDescription');
      print('❌ Full Error: $error');
    }
  }
}