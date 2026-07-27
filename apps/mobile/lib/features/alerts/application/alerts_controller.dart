import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/alert_models.dart';
import '../data/alerts_api.dart';

final alertsApiProvider = Provider<AlertsApi>(
  (ref) => AlertsApi(ref.watch(apiClientProvider)),
);

/// `null` = sin filtro (todas). Por defecto se muestran las abiertas, que es
/// lo que de verdad requiere atención (FUNCTIONAL_REQUIREMENTS.md §15).
final alertStatusFilterProvider = StateProvider<String?>((ref) => 'open');

final alertsListProvider = FutureProvider.autoDispose<List<Alert>>((ref) {
  final status = ref.watch(alertStatusFilterProvider);
  return ref.watch(alertsApiProvider).list(status: status);
});
