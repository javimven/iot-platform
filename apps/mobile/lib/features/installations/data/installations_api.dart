import '../../../core/api/api_client.dart';
import 'installation_models.dart';

class InstallationsApi {
  final ApiClient _client;

  InstallationsApi(this._client);

  Future<List<Installation>> list() async {
    // `GET /installations` devuelve hoy un array plano, no el sobre
    // `{data, meta}` que documenta OPENAPI.yaml (paginación aún sin
    // implementar en el backend para ningún listado salvo auditoría —
    // gap real de contrato, ver BACKLOG.md).
    final list = await _client.getJsonList('/installations');
    return list.map((e) => Installation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Installation> getOne(String id) async {
    final json = await _client.getJson('/installations/$id');
    return Installation.fromJson(json);
  }

  Future<List<LatestReading>> latestReadings(String installationId) async {
    final list = await _client.getJsonList('/installations/$installationId/latest-readings');
    return list.map((e) => LatestReading.fromJson(e as Map<String, dynamic>)).toList();
  }
}
