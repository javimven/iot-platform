import '../../../core/api/api_client.dart';
import '../../sessions/data/sessions_models.dart';
import 'members_models.dart';

/// Llamadas HTTP crudas a `/members*` (OPENAPI.yaml, `PERMISSIONS.md` §1 —
/// todo esto requiere el rol `org_admin`, el backend ya lo exige vía
/// `RequirePermission`, esto solo llama a los endpoints).
class MembersApi {
  final ApiClient _client;

  MembersApi(this._client);

  Future<List<Member>> list() async {
    final list = await _client.getJsonList('/members');
    return list.map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Member> invite({required String email, required String roleCode}) async {
    final json = await _client.postJson('/members', body: {
      'email': email,
      'roleCode': roleCode,
    });
    return Member.fromJson(json);
  }

  Future<Member> updateRole(String memberId, {required String roleCode}) async {
    final json = await _client.patchJson('/members/$memberId', body: {'roleCode': roleCode});
    return Member.fromJson(json);
  }

  Future<Member> updateStatus(String memberId, {required String status}) async {
    final json = await _client.patchJson('/members/$memberId', body: {'status': status});
    return Member.fromJson(json);
  }

  /// Baja lógica — no elimina la cuenta de usuario, solo la membresía.
  Future<void> remove(String memberId) => _client.delete('/members/$memberId');

  /// Instalaciones a las que el miembro tiene acceso restringido (`PERMISSIONS.md`
  /// §2) — lista vacía significa "todas las de la organización" (sin restringir).
  Future<List<String>> getScope(String memberId) async {
    final list = await _client.getJsonList('/members/$memberId/scope');
    return list.cast<String>();
  }

  Future<void> setScope(String memberId, List<String> installationIds) {
    return _client.put('/members/$memberId/scope', body: {'installationIds': installationIds});
  }

  /// Sesiones activas de otro miembro (`sessions.read_others`, `BACKLOG.md` #14) —
  /// solo `org_admin`.
  Future<List<UserSession>> sessions(String memberId) async {
    final list = await _client.getJsonList('/members/$memberId/sessions');
    return list.map((e) => UserSession.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 204 idempotente incluso si ya no existe (mismo criterio que la propia sesión).
  Future<void> revokeSession(String memberId, String sessionId) =>
      _client.delete('/members/$memberId/sessions/$sessionId');
}
