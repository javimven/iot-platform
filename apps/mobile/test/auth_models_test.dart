import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/auth/data/auth_models.dart';

/// API_DESIGN.md §3: el login puede devolver AuthSuccess (accessToken) o
/// AuthOrgSelection (preAuthToken) — el modelo debe distinguirlos sin ambigüedad.
void main() {
  group('LoginResponse.fromJson', () {
    test('reconoce una respuesta AuthSuccess', () {
      final response = LoginResponse.fromJson({
        'accessToken': 'token-123',
        'refreshToken': {'sessionId': 'session-1', 'secret': 'secret-1'},
      });

      expect(response.success, isNotNull);
      expect(response.needsOrgSelection, isNull);
      expect(response.success!.accessToken, 'token-123');
      expect(response.success!.refreshSessionId, 'session-1');
    });

    test('reconoce una respuesta AuthOrgSelection', () {
      final response = LoginResponse.fromJson({
        'preAuthToken': 'pre-auth-token',
        'organizations': [
          {'organizationId': 'org-1', 'name': 'Finca A', 'roleCode': 'org_admin'},
        ],
      });

      expect(response.needsOrgSelection, isNotNull);
      expect(response.success, isNull);
      expect(response.needsOrgSelection!.organizations, hasLength(1));
      expect(response.needsOrgSelection!.organizations.first.name, 'Finca A');
    });
  });
}
