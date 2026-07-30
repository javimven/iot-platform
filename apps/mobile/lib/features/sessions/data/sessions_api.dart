import '../../../core/api/api_client.dart';
import 'sessions_models.dart';

class SessionsApi {
  final ApiClient _client;

  SessionsApi(this._client);

  Future<List<UserSession>> list() async {
    final list = await _client.getJsonList('/auth/sessions');
    return list.map((e) => UserSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 204 idempotente incluso si ya no existe (`PERMISSIONS.md` §9 — no se
  /// filtra si existía o era de otro usuario).
  Future<void> revoke(String sessionId) => _client.delete('/auth/sessions/$sessionId');
}
