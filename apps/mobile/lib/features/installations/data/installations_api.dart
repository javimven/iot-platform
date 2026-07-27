import '../../../core/api/api_client.dart';
import 'installation_models.dart';

class InstallationsApi {
  final ApiClient _client;

  InstallationsApi(this._client);

  Future<List<Installation>> list() async {
    final json = await _client.getJson('/installations');
    final data = json['data'] as List<dynamic>;
    return data.map((e) => Installation.fromJson(e as Map<String, dynamic>)).toList();
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
