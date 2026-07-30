import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../directory/data/directory_models.dart';
import '../../installations/data/installation_models.dart';
import '../data/platform_directory_api.dart';

final platformDirectoryApiProvider = Provider<PlatformDirectoryApi>(
  (ref) => PlatformDirectoryApi(ref.watch(apiClientProvider)),
);

final platformInstallationsProvider =
    FutureProvider.autoDispose.family<List<Installation>, String>((ref, organizationId) {
  return ref.watch(platformDirectoryApiProvider).installations(organizationId);
});

typedef _OrgAndInstallation = ({String organizationId, String installationId});

final platformZonesProvider =
    FutureProvider.autoDispose.family<List<Zone>, _OrgAndInstallation>((ref, params) {
  return ref
      .watch(platformDirectoryApiProvider)
      .zones(params.organizationId, params.installationId);
});

final platformGatewaysForInstallationProvider =
    FutureProvider.autoDispose.family<List<Gateway>, _OrgAndInstallation>((ref, params) {
  return ref
      .watch(platformDirectoryApiProvider)
      .gatewaysForInstallation(params.organizationId, params.installationId);
});

typedef _OrgAndGateway = ({String organizationId, String gatewayId});

final platformDevicesForGatewayProvider =
    FutureProvider.autoDispose.family<List<Device>, _OrgAndGateway>((ref, params) {
  return ref
      .watch(platformDirectoryApiProvider)
      .devicesForGateway(params.organizationId, params.gatewayId);
});

typedef _OrgAndDevice = ({String organizationId, String deviceId});

final platformSensorsForDeviceProvider =
    FutureProvider.autoDispose.family<List<Sensor>, _OrgAndDevice>((ref, params) {
  return ref
      .watch(platformDirectoryApiProvider)
      .sensorsForDevice(params.organizationId, params.deviceId);
});
