import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audit/data/audit_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../organization/data/organization_models.dart';
import '../data/platform_api.dart';
import '../data/platform_models.dart';

final platformApiProvider = Provider<PlatformApi>(
  (ref) => PlatformApi(ref.watch(apiClientProvider)),
);

final platformOrganizationsProvider = FutureProvider.autoDispose<List<OrganizationProfile>>((ref) {
  return ref.watch(platformApiProvider).listOrganizations();
});

final platformFeatureCatalogProvider = FutureProvider.autoDispose<List<Feature>>((ref) {
  return ref.watch(platformApiProvider).getFeatureCatalog();
});

final platformOrganizationFeaturesProvider =
    FutureProvider.autoDispose.family<List<OrganizationFeature>, String>((ref, organizationId) {
  return ref.watch(platformApiProvider).getOrganizationFeatures(organizationId);
});

final platformAuditLogProvider = FutureProvider.autoDispose<List<AuditLogEntry>>((ref) {
  return ref.watch(platformApiProvider).getAuditLog();
});
