import '../../../core/api/api_client.dart';
import 'parcel_models.dart';

/// Parcelas (BACKLOG.md #36). Rutas anidadas bajo la finca, como las zonas.
class ParcelsApi {
  final ApiClient _client;

  ParcelsApi(this._client);

  Future<List<Parcel>> deInstalacion(String installationId) async {
    final lista = await _client.getJsonList('/installations/$installationId/parcels');
    return lista.map((e) => Parcel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Parcel> crear({
    required String installationId,
    required String name,
    required ContornoParcela contorno,
    String? notes,
  }) async {
    final json = await _client.postJson('/installations/$installationId/parcels', body: {
      'name': name,
      'geometry': contorno.toGeoJson(),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return Parcel.fromJson(json);
  }

  Future<Parcel> renombrar(String parcelId, String name) async {
    final json = await _client.patchJson('/parcels/$parcelId', body: {'name': name});
    return Parcel.fromJson(json);
  }

  /// Redibujar el contorno sube su version en el backend: las observaciones
  /// anteriores se calcularon sobre el recinto viejo.
  Future<Parcel> redibujar(String parcelId, ContornoParcela contorno) async {
    final json = await _client.patchJson('/parcels/$parcelId', body: {
      'geometry': contorno.toGeoJson(),
    });
    return Parcel.fromJson(json);
  }

  Future<void> borrar(String parcelId) => _client.delete('/parcels/$parcelId');
}
