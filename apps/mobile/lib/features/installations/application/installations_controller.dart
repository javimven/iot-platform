import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/installation_models.dart';
import '../data/installations_api.dart';

final installationsApiProvider = Provider<InstallationsApi>(
  (ref) => InstallationsApi(ref.watch(apiClientProvider)),
);

final installationsListProvider = FutureProvider.autoDispose<List<Installation>>((ref) {
  return ref.watch(installationsApiProvider).list();
});

final installationProvider = FutureProvider.autoDispose.family<Installation, String>((ref, id) {
  return ref.watch(installationsApiProvider).getOne(id);
});

final latestReadingsProvider =
    FutureProvider.autoDispose.family<List<LatestReading>, String>((ref, installationId) {
  return ref.watch(installationsApiProvider).latestReadings(installationId);
});
