import '../../../core/api/api_client.dart';
import 'alert_models.dart';

class AlertsApi {
  final ApiClient _client;

  AlertsApi(this._client);

  /// `status` opcional (`open`/`acknowledged`/`resolved`) — sin filtro, el
  /// backend devuelve todas (API_DESIGN.md, `AlertsController.findAll`).
  Future<List<Alert>> list({String? status}) async {
    final list = await _client.getJsonList(
      '/alerts',
      query: status == null ? null : {'status': status},
    );
    return list.map((e) => Alert.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> acknowledge(String id) => _client.post('/alerts/$id/acknowledge');

  Future<void> resolve(String id) => _client.post('/alerts/$id/resolve');
}
