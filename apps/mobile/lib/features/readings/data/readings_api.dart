import '../../../core/api/api_client.dart';
import 'reading_history_models.dart';

class ReadingsApi {
  final ApiClient _client;

  ReadingsApi(this._client);

  /// `granularity`: `raw` (máx. 7 días de rango, ReadingsService), `hourly`
  /// o `daily` — nunca elegida libremente por el usuario más allá de los
  /// presets de la UI (API_DESIGN.md §8: no es el cliente quien decide la
  /// función de agregación, solo la ventana de tiempo).
  ///
  /// Con `organizationId`, por la ruta de plataforma (ADR-0007, Admin de
  /// plataforma); sin él, por la de miembro.
  Future<List<HistoryPoint>> history({
    required String channelId,
    required DateTime from,
    required DateTime to,
    required String granularity,
    String? organizationId,
  }) async {
    final prefix = organizationId == null ? '' : '/platform/organizations/$organizationId';
    final list = await _client.getJsonList(
      '$prefix/channels/$channelId/readings',
      query: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'granularity': granularity,
      },
    );
    return list.map((e) => HistoryPoint.fromJson(e as Map<String, dynamic>)).toList();
  }
}
