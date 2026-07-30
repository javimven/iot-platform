import '../../../core/api/api_client.dart';
import '../../audit/data/audit_models.dart';
import '../../organization/data/organization_models.dart';
import 'platform_models.dart';

/// Llamadas de plataforma (`PERMISSIONS.md` §3/§14) — sin organización
/// activa, requieren `isPlatformAdmin`.
class PlatformApi {
  final ApiClient _client;

  PlatformApi(this._client);

  Future<List<OrganizationProfile>> listOrganizations() async {
    final list = await _client.getJsonList('/platform/organizations');
    return list.map((e) => OrganizationProfile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrganizationProfile> createOrganization({
    required String name,
    required String contactEmail,
    required String firstAdminEmail,
  }) async {
    final json = await _client.postJson('/platform/organizations', body: {
      'name': name,
      'contactEmail': contactEmail,
      'firstAdminEmail': firstAdminEmail,
    });
    return OrganizationProfile.fromJson(json);
  }

  Future<void> suspendOrganization(String id) => _client.post('/platform/organizations/$id/suspend');

  Future<void> reactivateOrganization(String id) =>
      _client.post('/platform/organizations/$id/reactivate');

  Future<List<Feature>> getFeatureCatalog() async {
    final list = await _client.getJsonList('/platform/features');
    return list.map((e) => Feature.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OrganizationFeature>> getOrganizationFeatures(String organizationId) async {
    final list = await _client.getJsonList('/platform/organizations/$organizationId/features');
    return list.map((e) => OrganizationFeature.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setOrganizationFeatures(
    String organizationId,
    List<({String featureCode, bool enabled})> updates,
  ) {
    return _client.put('/platform/organizations/$organizationId/features', body: [
      for (final u in updates) {'featureCode': u.featureCode, 'enabled': u.enabled},
    ]);
  }

  Future<List<AuditLogEntry>> getAuditLog() async {
    final list = await _client.getJsonList('/platform/audit-log');
    return list.map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>)).toList();
  }
}
