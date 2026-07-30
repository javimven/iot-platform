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
}
