/// Espejo del error RFC 7807 de la API (API_DESIGN.md §4). Nunca contiene
/// detalle interno del servidor — solo lo que el backend ya decidió exponer.
class ApiException implements Exception {
  final int status;
  final String type;
  final String title;
  final String? detail;
  final List<ApiFieldError> errors;

  const ApiException({
    required this.status,
    required this.type,
    required this.title,
    this.detail,
    this.errors = const [],
  });

  factory ApiException.fromJson(int status, Map<String, dynamic> json) {
    return ApiException(
      status: status,
      type: (json['type'] as String?) ?? 'error',
      title: (json['title'] as String?) ?? 'Unexpected error',
      detail: json['detail'] as String?,
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => ApiFieldError.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  factory ApiException.network() => const ApiException(
        status: 0,
        type: 'network-error',
        title: 'No se pudo conectar con el servidor',
      );

  @override
  String toString() => 'ApiException($status, $type): $title';
}

class ApiFieldError {
  final String field;
  final String message;

  const ApiFieldError({required this.field, required this.message});

  factory ApiFieldError.fromJson(Map<String, dynamic> json) => ApiFieldError(
        field: json['field'] as String? ?? '',
        message: json['message'] as String? ?? '',
      );
}
