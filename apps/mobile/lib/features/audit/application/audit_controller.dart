import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/audit_api.dart';
import '../data/audit_models.dart';

final auditApiProvider = Provider<AuditApi>(
  (ref) => AuditApi(ref.watch(apiClientProvider)),
);

final auditLogProvider = FutureProvider.autoDispose<List<AuditLogEntry>>((ref) {
  return ref.watch(auditApiProvider).list();
});
