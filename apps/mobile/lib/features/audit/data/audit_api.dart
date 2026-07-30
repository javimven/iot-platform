import '../../../core/api/api_client.dart';
import 'audit_models.dart';

class AuditApi {
  final ApiClient _client;

  AuditApi(this._client);

  Future<List<AuditLogEntry>> list() async {
    final list = await _client.getJsonList('/audit-log');
    return list.map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>)).toList();
  }
}
