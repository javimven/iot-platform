/// Desacopla `ApiClient` (Dio) del controlador de autenticación (Riverpod) —
/// evita una dependencia circular entre "quién hace las peticiones HTTP" y
/// "quién gestiona el estado de sesión" (ARCHITECTURE.md §6).
abstract class AuthTokenDelegate {
  String? get accessToken;

  /// Intenta refrescar el access token (refresh rotativo, API_DESIGN.md §3).
  /// Devuelve `true` si se consiguió un token nuevo.
  Future<bool> refreshSession();

  /// Se llama cuando el refresh también falla — la sesión ya no es válida.
  Future<void> forceLogout();
}
