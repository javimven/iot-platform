import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/members_api.dart';
import '../data/members_models.dart';

final membersApiProvider = Provider<MembersApi>(
  (ref) => MembersApi(ref.watch(apiClientProvider)),
);

final membersListProvider = FutureProvider.autoDispose<List<Member>>((ref) {
  return ref.watch(membersApiProvider).list();
});

final memberScopeProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, memberId) {
  return ref.watch(membersApiProvider).getScope(memberId);
});
