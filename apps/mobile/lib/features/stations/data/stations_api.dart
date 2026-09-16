import '../../../core/api/api_client.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';

/// Cliente de la pantalla "Estaciones" (BACKLOG.md #30) — reutiliza los
/// modelos `Gateway`/`LatestReading` ya existentes en vez de duplicarlos,
/// mismo patrón que ya usa `platform` con estos dos modelos.
class StationsApi {
  final ApiClient _client;

  StationsApi(this._client);

  /// Todas las estaciones (gateways) de la organización, sin filtrar por
  /// instalación — mismo endpoint que `DirectoryApi.gatewaysForInstallation`
  /// (`GET /gateways` no filtra por instalación, BACKLOG.md #13), aquí sin
  /// el `.where` porque queremos todas.
  Future<List<Gateway>> allGateways() async {
    final list = await _client.getJsonList('/gateways');
    return list.map((e) => Gateway.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LatestReading>> latestReadingsForGateway(String gatewayId) async {
    final list = await _client.getJsonList('/gateways/$gatewayId/latest-readings');
    return list.map((e) => LatestReading.fromJson(e as Map<String, dynamic>)).toList();
  }
}
