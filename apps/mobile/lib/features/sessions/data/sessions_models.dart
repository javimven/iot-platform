/// Espejo de `Session` (OPENAPI.yaml, `/auth/sessions`) — sesiones activas
/// del propio usuario (`sessions.read_own`/`revoke_own`, `PERMISSIONS.md` §1).
class UserSession {
  final String id;
  final String? userAgent;
  final String? ipAddress;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  const UserSession({
    required this.id,
    required this.userAgent,
    required this.ipAddress,
    required this.createdAt,
    required this.lastUsedAt,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        id: json['id'] as String,
        userAgent: json['userAgent'] as String?,
        ipAddress: json['ipAddress'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      );
}
