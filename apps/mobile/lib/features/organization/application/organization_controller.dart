import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/organization_api.dart';
import '../data/organization_models.dart';

final organizationApiProvider = Provider<OrganizationApi>(
  (ref) => OrganizationApi(ref.watch(apiClientProvider)),
);

final organizationProfileProvider = FutureProvider.autoDispose<OrganizationProfile>((ref) {
  return ref.watch(organizationApiProvider).getProfile();
});

final organizationFeaturesProvider = FutureProvider.autoDispose<List<OrganizationFeature>>((ref) {
  return ref.watch(organizationApiProvider).getFeatures();
});
