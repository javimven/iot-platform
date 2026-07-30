import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/sessions/data/sessions_models.dart';

void main() {
  group('UserSession.fromJson', () {
    test('parsea una sesión con userAgent/ipAddress conocidos', () {
      final session = UserSession.fromJson({
        'id': 'session-1',
        'userAgent': 'Mozilla/5.0 (Windows NT 10.0)',
        'ipAddress': '203.0.113.5',
        'createdAt': '2026-07-20T10:00:00.000Z',
        'lastUsedAt': '2026-07-29T18:00:00.000Z',
      });

      expect(session.userAgent, contains('Windows'));
      expect(session.ipAddress, '203.0.113.5');
    });

    test('tolera userAgent/ipAddress nulos', () {
      final session = UserSession.fromJson({
        'id': 'session-2',
        'userAgent': null,
        'ipAddress': null,
        'createdAt': '2026-07-20T10:00:00.000Z',
        'lastUsedAt': '2026-07-29T18:00:00.000Z',
      });

      expect(session.userAgent, isNull);
      expect(session.ipAddress, isNull);
    });
  });
}
