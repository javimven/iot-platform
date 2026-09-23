import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

  /// Para las rutas que devuelven un objeto **o** nada cuando todavía no hay
  /// dato — la última observación de satélite de una parcela recién creada, por
  /// ejemplo. `getJson` no sirve ahí: haría un cast y reventaría.
  ///
  /// Ojo: NestJS no manda el JSON `null` cuando un controlador devuelve
  /// `null`, manda un 200 **con el cuerpo vacío**, y dio lo entrega como `""`.
  /// La primera versión solo contemplaba `null` y en la web compilada salía
  /// "Runtime type check failed" (2026-09-22).
  Future<Map<String, dynamic>?> getJsonOrNull(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _guard(() => _dio.get<dynamic>(path, queryParameters: query));
    return comoObjetoOVacio(response.data);
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

  /// Descarga de un fichero generado por la API (el cuaderno exportado). Se
  /// piden los bytes con la sesión puesta, porque el token va en la cabecera y
  /// una descarga del navegador no la llevaría.
  Future<({List<int> bytes, String? nombre, String mediaType})> getBytes(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _guard(
      () => _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    final cabecera = response.headers.value('content-disposition');
    return (
      bytes: (response.data as List<int>?) ?? const <int>[],
      nombre: nombreDeLaCabecera(cabecera),
      mediaType: response.headers.value('content-type') ?? 'application/octet-stream',
    );
  }

  /// Subida de un archivo (`multipart/form-data`): las fotos y documentos del
  /// cuaderno. El archivo va en memoria y en el campo `file`, que es el que
  /// espera el backend; el resto de campos viajan como texto, porque en un
  /// `multipart` no hay tipos.
  Future<Map<String, dynamic>> postArchivo(
    String path, {
    required List<int> bytes,
    required String filename,
    Map<String, String> campos = const {},
  }) async {
    final formulario = FormData.fromMap({
      ...campos,
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _guard(() => _dio.post<dynamic>(path, data: formulario));
    return response.data as Map<String, dynamic>;
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

/// Traduce la respuesta de una ruta que puede no tener dato: `null` o cuerpo
/// vacío (lo que manda NestJS cuando el controlador devuelve `null`) son "no
/// hay nada"; un objeto es el dato. Cualquier otra cosa es un contrato roto y
/// se dice claro, en vez de un "Runtime type check failed" sin más.
@visibleForTesting
Map<String, dynamic>? comoObjetoOVacio(Object? data) {
  if (data == null) return null;
  if (data is String && data.trim().isEmpty) return null;
  if (data is Map<String, dynamic>) return data;
  throw const FormatException('Respuesta inesperada del servidor: se esperaba un objeto o nada');
}

/// El nombre con el que guardar una descarga, sacado de `Content-Disposition`:
/// `attachment; filename="x.pdf"; filename*=UTF-8''x%20con%20acentos.pdf`.
///
/// Se prefiere `filename*`, que es el que trae los acentos bien; `filename` a
/// secas es la reserva para clientes antiguos y viene sin ellos.
@visibleForTesting
String? nombreDeLaCabecera(String? cabecera) {
  if (cabecera == null) return null;
  final utf8 = RegExp(r"filename\*=UTF-8''([^;]+)").firstMatch(cabecera);
  if (utf8 != null) {
    return Uri.decodeComponent(utf8.group(1)!.trim());
  }
  final simple = RegExp('filename="([^"]+)"').firstMatch(cabecera);
  return simple?.group(1);
}
