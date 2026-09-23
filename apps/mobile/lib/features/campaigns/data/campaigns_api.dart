import '../../../core/api/api_client.dart';
import 'activity_models.dart';
import 'campaign_models.dart';
import 'document_models.dart';
import 'notebook_models.dart';

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

  /// Qué falta en el cuaderno. En una campaña sencilla, `aplica` es falso.
  Future<RevisionDelCuaderno> revision(String campaignId) async =>
      RevisionDelCuaderno.fromJson(await _client.getJson('/campaigns/$campaignId/completeness'));

  /// Pasar a cuaderno completo con las respuestas del asistente. No copia ni
  /// borra nada: lo ya registrado sirve de base (ADR-0013).
  Future<Campana> completarCuaderno(String id, Map<String, bool> perfil) async =>
      Campana.fromJson(await _client.postJson('/campaigns/$id/upgrade', body: {
        'notebookProfile': perfil,
      }));

  /// Cambiar las respuestas de una campaña que ya es un cuaderno completo.
  Future<Campana> guardarPerfil(String id, Map<String, bool> perfil) async =>
      Campana.fromJson(await _client.patchJson('/campaigns/$id', body: {
        'notebookProfile': perfil,
      }));

  Future<List<PersonaCuaderno>> personas({String? installationId}) async {
    final lista = await _client.getJsonList('/notebook/people', query: {
      if (installationId != null) 'installationId': installationId,
    });
    return lista.map((e) => PersonaCuaderno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PersonaCuaderno> crearPersona(Map<String, dynamic> cuerpo) async =>
      PersonaCuaderno.fromJson(await _client.postJson('/notebook/people', body: cuerpo));

  Future<PersonaCuaderno> cambiarPersona(String id, Map<String, dynamic> cuerpo) async =>
      PersonaCuaderno.fromJson(await _client.patchJson('/notebook/people/$id', body: cuerpo));

  Future<void> borrarPersona(String id) => _client.delete('/notebook/people/$id');

  Future<List<EquipoCuaderno>> equipos({String? installationId}) async {
    final lista = await _client.getJsonList('/notebook/equipment', query: {
      if (installationId != null) 'installationId': installationId,
    });
    return lista.map((e) => EquipoCuaderno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<EquipoCuaderno> crearEquipo(Map<String, dynamic> cuerpo) async =>
      EquipoCuaderno.fromJson(await _client.postJson('/notebook/equipment', body: cuerpo));

  Future<EquipoCuaderno> cambiarEquipo(String id, Map<String, dynamic> cuerpo) async =>
      EquipoCuaderno.fromJson(await _client.patchJson('/notebook/equipment/$id', body: cuerpo));

  Future<void> borrarEquipo(String id) => _client.delete('/notebook/equipment/$id');

  /// Los documentos de la campaña y los de sus actividades, de una vez: así la
  /// línea de tiempo puede marcar cuáles llevan foto sin una petición por cada
  /// actividad.
  Future<List<DocumentoDelCuaderno>> documentos(String campaignId) async {
    final lista = await _client.getJsonList('/campaigns/$campaignId/documents');
    return lista.map((e) => DocumentoDelCuaderno.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DocumentoDelCuaderno> adjuntar(
    String campaignId, {
    String? activityId,
    required List<int> bytes,
    required String filename,
    String documentType = 'photo',
    String? title,
  }) async {
    final ruta = activityId == null
        ? '/campaigns/$campaignId/documents'
        : '/campaigns/$campaignId/activities/$activityId/documents';
    return DocumentoDelCuaderno.fromJson(
      await _client.postArchivo(
        ruta,
        bytes: bytes,
        filename: filename,
        campos: {
          'documentType': documentType,
          if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        },
      ),
    );
  }

  Future<void> quitarDocumento(String campaignId, String documentId, {String? activityId}) {
    final ruta = activityId == null
        ? '/campaigns/$campaignId/documents/$documentId'
        : '/campaigns/$campaignId/activities/$activityId/documents/$documentId';
    return _client.delete(ruta);
  }
}
