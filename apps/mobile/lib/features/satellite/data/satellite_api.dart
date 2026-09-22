import '../../../core/api/api_client.dart';
import 'satellite_models.dart';

/// Lectura del modulo de satelite (BACKLOG.md #36). Todo cuelga de la parcela.
class SatelliteApi {
  final ApiClient _client;

  SatelliteApi(this._client);

  /// `null` si la parcela todavia no tiene ninguna observacion utilizable:
  /// acaba de crearse, o las pasadas estaban demasiado tapadas.
  Future<ObservacionSatelite?> ultima(String parcelId) async {
    // El backend devuelve `null` cuando no hay ninguna todavia; `getJson`
    // espera un objeto, asi que se mira antes de convertirlo.
    final json = await _client.getJsonOrNull('/parcels/$parcelId/satellite/latest');
    return json == null ? null : ObservacionSatelite.fromJson(json);
  }

  Future<List<ObservacionSatelite>> observaciones(
    String parcelId, {
    DateTime? from,
    DateTime? to,
    bool incluirDescartadas = false,
  }) async {
    final lista = await _client.getJsonList(
      '/parcels/$parcelId/satellite/observations',
      query: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        if (incluirDescartadas) 'includeRejected': 'true',
      },
    );
    return lista.map((e) => ObservacionSatelite.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PuntoSatelite>> serie(String parcelId, {DateTime? from, DateTime? to}) async {
    final lista = await _client.getJsonList(
      '/parcels/$parcelId/satellite/timeseries',
      query: {
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
      },
    );
    return lista.map((e) => PuntoSatelite.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Enlace firmado y temporal. Nunca se guarda: se pide cuando hace falta.
  Future<EnlaceAsset> enlaceDeAsset({
    required String parcelId,
    required String observationId,
    required String assetId,
  }) async {
    final json = await _client.getJson(
      '/parcels/$parcelId/satellite/observations/$observationId/assets/$assetId/url',
    );
    return EnlaceAsset.fromJson(json);
  }

  /// Fuerza una busqueda. El backend responde 429 si ya se hizo hace menos de
  /// una hora: gasta cuota de Copernicus.
  Future<void> refrescar(String parcelId) =>
      _client.post('/parcels/$parcelId/satellite/refresh');
}
