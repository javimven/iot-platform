import '../../../core/api/api_client.dart';
import 'activity_models.dart';
import 'campaign_models.dart';

/// Campañas y cuaderno de campo (BACKLOG.md #60). Contrato en OPENAPI.yaml
/// y API_DESIGN.md §17 ter.
class CampaignsApi {
  CampaignsApi(this._client);

  final ApiClient _client;

  Future<List<CampanaResumida>> listar({String? status, String? installationId}) async {
    final lista = await _client.getJsonList('/campaigns', query: {
      if (status != null) 'status': status,
      if (installationId != null) 'installationId': installationId,
    });
    return lista.map((e) => CampanaResumida.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Campana> ficha(String id) async =>
      Campana.fromJson(await _client.getJson('/campaigns/$id'));

  Future<Campana> crear(String installationId, NuevaCampana campana) async => Campana.fromJson(
        await _client.postJson('/installations/$installationId/campaigns', body: campana.toJson()),
      );

  Future<Campana> cerrar(
    String id, {
    required DateTime endDate,
    double? declaredProductionKg,
    String? closingNotes,
  }) async =>
      Campana.fromJson(await _client.postJson('/campaigns/$id/close', body: {
        'endDate': escribirFecha(endDate),
        if (declaredProductionKg != null) 'declaredProductionKg': declaredProductionKg,
        if (closingNotes != null && closingNotes.trim().isNotEmpty)
          'closingNotes': closingNotes.trim(),
      }));

  Future<Campana> reabrir(String id, String motivo) async => Campana.fromJson(
        await _client.postJson('/campaigns/$id/reopen', body: {'reason': motivo.trim()}),
      );

  Future<void> borrar(String id) => _client.delete('/campaigns/$id');

  Future<List<CultivoCatalogo>> cultivos() async {
    final lista = await _client.getJsonList('/crops');
    return lista.map((e) => CultivoCatalogo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Actividad>> actividades(String campaignId) async {
    final lista = await _client.getJsonList('/campaigns/$campaignId/activities');
    return lista.map((e) => Actividad.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Actividad> registrar(String campaignId, Map<String, dynamic> cuerpo) async =>
      Actividad.fromJson(await _client.postJson('/campaigns/$campaignId/activities', body: cuerpo));

  Future<Actividad> corregir(
          String campaignId, String activityId, Map<String, dynamic> cuerpo) async =>
      Actividad.fromJson(
        await _client.patchJson('/campaigns/$campaignId/activities/$activityId', body: cuerpo),
      );

  /// El motivo va en la consulta: un cuerpo en un DELETE lo tiran algunos proxies.
  Future<void> borrarActividad(String campaignId, String activityId, {String? motivo}) {
    final consulta = motivo == null || motivo.trim().isEmpty
        ? ''
        : '?reason=${Uri.encodeQueryComponent(motivo.trim())}';
    return _client.delete('/campaigns/$campaignId/activities/$activityId$consulta');
  }

  Future<ResumenCampana> resumen(String campaignId) async =>
      ResumenCampana.fromJson(await _client.getJson('/campaigns/$campaignId/summary'));
}
