import '../../../core/api/api_client.dart';
import 'organization_models.dart';

class OrganizationApi {
  final ApiClient _client;

  OrganizationApi(this._client);

  Future<OrganizationProfile> getProfile() async {
    final json = await _client.getJson('/organization');
    return OrganizationProfile.fromJson(json);
  }

  Future<OrganizationProfile> updateProfile({String? name, String? contactEmail}) async {
    final json = await _client.patchJson('/organization', body: {
      if (name != null) 'name': name,
      if (contactEmail != null) 'contactEmail': contactEmail,
    });
    return OrganizationProfile.fromJson(json);
  }

  Future<List<OrganizationFeature>> getFeatures() async {
    final list = await _client.getJsonList('/organization/features');
    return list.map((e) => OrganizationFeature.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<OrgChannelThreshold>> getChannelThresholds() async {
    final list = await _client.getJsonList('/organization/channel-thresholds');
    return list.map((e) => OrgChannelThreshold.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setChannelThreshold(
    String channelTypeCode, {
    double? defaultMin,
    double? defaultMax,
  }) {
    return _client.put('/organization/channel-thresholds/$channelTypeCode', body: {
      'defaultMin': defaultMin,
      'defaultMax': defaultMax,
    });
  }

  /// Catálogo completo de tipos de canal (`GET /channel-types`, cualquier
  /// usuario autenticado) — solo los códigos, para saber sobre cuáles se
  /// puede definir un umbral por defecto. Las etiquetas legibles ya las
  /// resuelve `ChannelTypeLabels` en cliente (no viajan en este catálogo).
  Future<List<String>> getChannelTypeCodes() async {
    final list = await _client.getJsonList('/channel-types');
    return list.map((e) => (e as Map<String, dynamic>)['code'] as String).toList();
  }
}
