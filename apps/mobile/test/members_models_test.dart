import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/members/data/members_models.dart';

/// SECURITY.md §7: la respuesta real de `GET /members` es plana
/// (`email`/`fullName` en el propio objeto, nunca un `user` anidado con
/// `passwordHash`) — el modelo solo debe saber leer esa forma.
void main() {
  group('Member.fromJson', () {
    test('parsea un miembro invitado, todavía sin activar (activatedAt nulo)', () {
      final member = Member.fromJson({
        'id': 'member-1',
        'userId': 'user-1',
        'email': 'nuevo@example.com',
        'fullName': 'nuevo@example.com',
        'roleCode': 'technician',
        'status': 'invited',
        'invitedAt': '2026-07-29T10:00:00.000Z',
        'activatedAt': null,
      });

      expect(member.email, 'nuevo@example.com');
      expect(member.status, 'invited');
      expect(member.activatedAt, isNull);
    });

    test('parsea un miembro activo', () {
      final member = Member.fromJson({
        'id': 'member-2',
        'userId': 'user-2',
        'email': 'admin@example.com',
        'fullName': 'Admin Org',
        'roleCode': 'org_admin',
        'status': 'active',
        'invitedAt': '2026-07-20T10:00:00.000Z',
        'activatedAt': '2026-07-21T10:00:00.000Z',
      });

      expect(member.roleCode, 'org_admin');
      expect(member.activatedAt, isNotNull);
    });
  });

  group('memberRoleLabel / memberStatusLabel', () {
    test('devuelve etiquetas en español para los códigos conocidos', () {
      expect(memberRoleLabel('org_admin'), 'Administrador');
      expect(memberRoleLabel('read_only'), 'Solo lectura');
      expect(memberStatusLabel('invited'), contains('Invitado'));
      expect(memberStatusLabel('suspended'), 'Suspendido');
    });

    test('un código desconocido devuelve el propio código en vez de lanzar', () {
      expect(memberRoleLabel('unknown_role'), 'unknown_role');
      expect(memberStatusLabel('unknown_status'), 'unknown_status');
    });
  });
}
