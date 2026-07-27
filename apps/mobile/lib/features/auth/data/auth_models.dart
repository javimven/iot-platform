/// Espejo de `AuthSuccess` (OPENAPI.yaml) — login/selección de organización/
/// refresh siempre devuelven esta forma cuando hay éxito completo.
class AuthSuccessResult {
  final String accessToken;
  final String refreshSessionId;
  final String refreshSecret;

  const AuthSuccessResult({
    required this.accessToken,
    required this.refreshSessionId,
    required this.refreshSecret,
  });

  factory AuthSuccessResult.fromJson(Map<String, dynamic> json) {
    final refreshToken = json['refreshToken'] as Map<String, dynamic>;
    return AuthSuccessResult(
      accessToken: json['accessToken'] as String,
      refreshSessionId: refreshToken['sessionId'] as String,
      refreshSecret: refreshToken['secret'] as String,
    );
  }
}

class OrganizationOption {
  final String organizationId;
  final String name;
  final String roleCode;

  const OrganizationOption({
    required this.organizationId,
    required this.name,
    required this.roleCode,
  });

  factory OrganizationOption.fromJson(Map<String, dynamic> json) => OrganizationOption(
        organizationId: json['organizationId'] as String,
        name: json['name'] as String,
        roleCode: json['roleCode'] as String,
      );
}

/// Espejo de `AuthOrgSelection` — API_DESIGN.md §3: se recibe cuando el
/// usuario tiene más de una membresía activa.
class AuthOrgSelectionResult {
  final String preAuthToken;
  final List<OrganizationOption> organizations;

  const AuthOrgSelectionResult({required this.preAuthToken, required this.organizations});

  factory AuthOrgSelectionResult.fromJson(Map<String, dynamic> json) => AuthOrgSelectionResult(
        preAuthToken: json['preAuthToken'] as String,
        organizations: (json['organizations'] as List<dynamic>)
            .map((e) => OrganizationOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// El backend devuelve una de las dos formas; se distingue por la presencia
/// de `accessToken` vs. `preAuthToken` (API_DESIGN.md §3).
class LoginResponse {
  final AuthSuccessResult? success;
  final AuthOrgSelectionResult? needsOrgSelection;

  const LoginResponse._({this.success, this.needsOrgSelection});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('accessToken')) {
      return LoginResponse._(success: AuthSuccessResult.fromJson(json));
    }
    return LoginResponse._(needsOrgSelection: AuthOrgSelectionResult.fromJson(json));
  }
}

/// Perfil propio (`GET /me`, OPENAPI.yaml).
class MeProfile {
  final String userId;
  final String? fullName;
  final String? email;
  final bool isPlatformAdmin;
  final String? activeOrganizationId;
  final String? roleCode;

  const MeProfile({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.isPlatformAdmin,
    required this.activeOrganizationId,
    required this.roleCode,
  });

  factory MeProfile.fromJson(Map<String, dynamic> json) => MeProfile(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String?,
        email: json['email'] as String?,
        isPlatformAdmin: json['isPlatformAdmin'] as bool? ?? false,
        activeOrganizationId: json['activeOrganizationId'] as String?,
        roleCode: json['roleCode'] as String?,
      );
}
