import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/sessions_api.dart';
import '../data/sessions_models.dart';

final sessionsApiProvider = Provider<SessionsApi>(
  (ref) => SessionsApi(ref.watch(apiClientProvider)),
);

final sessionsListProvider = FutureProvider.autoDispose<List<UserSession>>((ref) {
  return ref.watch(sessionsApiProvider).list();
});
