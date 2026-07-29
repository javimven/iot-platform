/// Espejo de `Member` (OPENAPI.yaml) — email/fullName vienen aplanados
/// (no un objeto `user` anidado), tal y como lo devuelve `GET /members` tras
/// el fix de SECURITY.md §7 (el `user` anidado incluía el hash de la
/// contraseña; ahora el backend nunca lo pide ni lo devuelve).
class Member {
  final String id;
  final String userId;
  final String email;
  final String fullName;
  final String roleCode;
  final String status;
  final DateTime? invitedAt;
  final DateTime? activatedAt;

  const Member({
    required this.id,
    required this.userId,
    required this.email,
    required this.fullName,
    required this.roleCode,
    required this.status,
    this.invitedAt,
    this.activatedAt,
  });

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        userId: json['userId'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        roleCode: json['roleCode'] as String,
        status: json['status'] as String,
        invitedAt: json['invitedAt'] != null ? DateTime.parse(json['invitedAt'] as String) : null,
        activatedAt:
            json['activatedAt'] != null ? DateTime.parse(json['activatedAt'] as String) : null,
      );
}

/// Roles válidos (`PERMISSIONS.md` §1) — mismo orden que `ROLE_CODES` en el
/// backend (`common/permissions/permissions.ts`).
const List<String> memberRoleCodes = ['org_admin', 'technician', 'operator', 'read_only'];

String memberRoleLabel(String roleCode) {
  switch (roleCode) {
    case 'org_admin':
      return 'Administrador';
    case 'technician':
      return 'Técnico';
    case 'operator':
      return 'Operador';
    case 'read_only':
      return 'Solo lectura';
    default:
      return roleCode;
  }
}

String memberStatusLabel(String status) {
  switch (status) {
    case 'invited':
      return 'Invitado (pendiente de activar)';
    case 'active':
      return 'Activo';
    case 'suspended':
      return 'Suspendido';
    default:
      return status;
  }
}
