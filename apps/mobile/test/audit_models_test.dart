import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/audit/data/audit_models.dart';

void main() {
  group('AuditLogEntry.fromJson', () {
    test('parsea una entrada con metadata y target', () {
      final entry = AuditLogEntry.fromJson({
        'id': '42',
        'actorUserId': 'user-1',
        'action': 'members.invite',
        'targetType': 'member',
        'targetId': 'member-1',
        'metadata': {'email': 'a@example.com', 'roleCode': 'technician'},
        'createdAt': '2026-07-30T10:00:00.000Z',
      });

      expect(entry.action, 'members.invite');
      expect(entry.metadata?['roleCode'], 'technician');
    });

    test('parsea una entrada sin target ni metadata (login)', () {
      final entry = AuditLogEntry.fromJson({
        'id': '1',
        'actorUserId': null,
        'action': 'auth.login',
        'targetType': null,
        'targetId': null,
        'metadata': null,
        'createdAt': '2026-07-30T10:00:00.000Z',
      });

      expect(entry.targetType, isNull);
      expect(entry.metadata, isNull);
    });
  });
}
