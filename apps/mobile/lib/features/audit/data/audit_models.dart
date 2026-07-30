/// Espejo de `AuditLogEntry` (OPENAPI.yaml, `GET /audit-log`) — las 200
/// entradas más recientes de la organización, sin filtro ni paginación
/// (`API_DESIGN.md` §5, `BACKLOG.md` #15: la paginación por cursor que
/// documentaba esto nunca se implementó de verdad).
class AuditLogEntry {
  /// `id` viaja como string, no número: es un `BigInt` en Postgres (bug real
  /// de serialización encontrado en vivo, 2026-07-30 — `JSON.stringify` no
  /// sabe serializar `BigInt`; el backend ahora lo convierte a string antes
  /// de enviarlo, ver `main.ts`). Un `int` de Dart/JS perdería precisión
  /// pasado 2^53 de todos modos, así que string es lo correcto aquí.
  final String id;
  final String? actorUserId;
  final String action;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const AuditLogEntry({
    required this.id,
    required this.actorUserId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.metadata,
    required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as String,
        actorUserId: json['actorUserId'] as String?,
        action: json['action'] as String,
        targetType: json['targetType'] as String?,
        targetId: json['targetId'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
