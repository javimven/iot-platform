import 'package:dio/dio.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'auth_token_delegate.dart';

/// Cliente HTTP único de la app (API_DESIGN.md). Añade el `Authorization:
/// Bearer` a cada petición (salvo las de auth, ya con rutas propias sin
/// necesitar token) y reintenta una vez tras un refresh si el servidor
/// responde 401 — nunca reintenta en bucle.
class ApiClient {
  final Dio _dio;
  AuthTokenDelegate? authDelegate;

  ApiClient() : _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = authDelegate?.accessToken;
          if (token != null && !_isAuthRoute(options.path)) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final isUnauthorized = error.response?.statusCode == 401;
          final alreadyRetried = error.requestOptions.extra['retried'] == true;

          if (isUnauthorized && !alreadyRetried && authDelegate != null) {
            final refreshed = await authDelegate!.refreshSession();
            if (refreshed) {
              try {
                final retryResponse = await _retry(error.requestOptions);
                handler.resolve(retryResponse);
                return;
              } on DioException catch (retryError) {
                handler.next(retryError);
                return;
              }
            }
            await authDelegate!.forceLogout();
          }
          handler.next(error);
        },
      ),
    );
  }

  Future<Response<dynamic>> _retry(RequestOptions requestOptions) {
    final options = Options(
      method: requestOptions.method,
      headers: {
        ...requestOptions.headers,
        'Authorization': 'Bearer ${authDelegate?.accessToken}',
      },
      extra: {'retried': true},
    );
    return _dio.request<dynamic>(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  bool _isAuthRoute(String path) => path.startsWith('/auth/');

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _guard(() => _dio.get<dynamic>(path, queryParameters: query));
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getJsonList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _guard(() => _dio.get<dynamic>(path, queryParameters: query));
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> postJson(String path, {Object? body}) async {
    final response = await _guard(() => _dio.post<dynamic>(path, data: body));
    return response.data as Map<String, dynamic>;
  }

  Future<void> post(String path, {Object? body}) async {
    await _guard(() => _dio.post<dynamic>(path, data: body));
  }

  Future<Map<String, dynamic>> patchJson(String path, {Object? body}) async {
    final response = await _guard(() => _dio.patch<dynamic>(path, data: body));
    return response.data as Map<String, dynamic>;
  }

  Future<void> put(String path, {Object? body}) async {
    await _guard(() => _dio.put<dynamic>(path, data: body));
  }

  Future<void> delete(String path) async {
    await _guard(() => _dio.delete<dynamic>(path));
  }

  Future<Response<dynamic>> _guard(Future<Response<dynamic>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      if (error.response == null) {
        throw ApiException.network();
      }
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        throw ApiException.fromJson(error.response!.statusCode ?? 0, data);
      }
      throw ApiException(
        status: error.response!.statusCode ?? 0,
        type: 'error',
        title: 'Unexpected error',
      );
    }
  }
}
