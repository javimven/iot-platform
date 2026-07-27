import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/directory_api.dart';
import '../data/directory_models.dart';

final directoryApiProvider = Provider<DirectoryApi>(
  (ref) => DirectoryApi(ref.watch(apiClientProvider)),
);

final zonesForInstallationProvider =
    FutureProvider.autoDispose.family<List<Zone>, String>((ref, installationId) {
  return ref.watch(directoryApiProvider).zonesForInstallation(installationId);
});

final gatewaysForInstallationProvider =
    FutureProvider.autoDispose.family<List<Gateway>, String>((ref, installationId) {
  return ref.watch(directoryApiProvider).gatewaysForInstallation(installationId);
});

final gatewayProvider = FutureProvider.autoDispose.family<Gateway, String>((ref, id) {
  return ref.watch(directoryApiProvider).getGateway(id);
});

final devicesForGatewayProvider =
    FutureProvider.autoDispose.family<List<Device>, String>((ref, gatewayId) {
  return ref.watch(directoryApiProvider).devicesForGateway(gatewayId);
});

final deviceProvider = FutureProvider.autoDispose.family<Device, String>((ref, id) {
  return ref.watch(directoryApiProvider).getDevice(id);
});

final sensorsForDeviceProvider =
    FutureProvider.autoDispose.family<List<Sensor>, String>((ref, deviceId) {
  return ref.watch(directoryApiProvider).sensorsForDevice(deviceId);
});

final sensorProvider = FutureProvider.autoDispose.family<Sensor, String>((ref, id) {
  return ref.watch(directoryApiProvider).getSensor(id);
});

final channelsForSensorProvider =
    FutureProvider.autoDispose.family<List<Channel>, String>((ref, sensorId) {
  return ref.watch(directoryApiProvider).channelsForSensor(sensorId);
});
