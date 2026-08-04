/// Configuración de la API (API_DESIGN.md, DEPLOYMENT.md §6).
///
/// Se fija en tiempo de compilación con `--dart-define=API_BASE_URL=...`
/// (Etapa 9: distintos valores para dev/staging/producción). Por defecto
/// apunta al backend local levantado con `docker-compose.yml`.
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
}
