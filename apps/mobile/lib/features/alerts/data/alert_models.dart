/// Espejo de `Alert` (OPENAPI.yaml) — FUNCTIONAL_REQUIREMENTS.md §15.
/// Los campos `installationName`/`channelTypeCode`/`deviceName`/`gatewayName`
/// son aditivos sobre el esquema documentado (API_DESIGN.md, añadidos en
/// Etapa 14 para que la lista muestre algo legible sin una llamada por fila).
class Alert {
  final String id;
  final String alertType;
  final String status;
  final DateTime openedAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final Map<String, dynamic>? details;
  final String? installationName;
  final String? channelTypeCode;
  final String? deviceName;
  final String? gatewayName;

  const Alert({
    required this.id,
    required this.alertType,
    required this.status,
    required this.openedAt,
    required this.acknowledgedAt,
    required this.resolvedAt,
    required this.details,
    required this.installationName,
    required this.channelTypeCode,
    required this.deviceName,
    required this.gatewayName,
  });

  factory Alert.fromJson(Map<String, dynamic> json) {
    final acknowledgedAtRaw = json['acknowledgedAt'] as String?;
    final resolvedAtRaw = json['resolvedAt'] as String?;
    return Alert(
      id: json['id'] as String,
      alertType: json['alertType'] as String,
      status: json['status'] as String,
      openedAt: DateTime.parse(json['openedAt'] as String),
      acknowledgedAt: acknowledgedAtRaw == null ? null : DateTime.parse(acknowledgedAtRaw),
      resolvedAt: resolvedAtRaw == null ? null : DateTime.parse(resolvedAtRaw),
      details: json['details'] as Map<String, dynamic>?,
      installationName: json['installationName'] as String?,
      channelTypeCode: json['channelTypeCode'] as String?,
      deviceName: json['deviceName'] as String?,
      gatewayName: json['gatewayName'] as String?,
    );
  }

  Alert copyWith({String? status, DateTime? acknowledgedAt, DateTime? resolvedAt}) => Alert(
        id: id,
        alertType: alertType,
        status: status ?? this.status,
        openedAt: openedAt,
        acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        details: details,
        installationName: installationName,
        channelTypeCode: channelTypeCode,
        deviceName: deviceName,
        gatewayName: gatewayName,
      );
}
