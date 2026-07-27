/// Espejos de `Zone`/`Gateway`/`Device`/`Sensor`/`Channel` (OPENAPI.yaml,
/// DATA_MODEL.md) — solo los campos que esta vista necesita mostrar
/// (FUNCTIONAL_REQUIREMENTS.md §4-9).
class Zone {
  final String id;
  final String installationId;
  final String name;
  final String? zoneType;

  const Zone({
    required this.id,
    required this.installationId,
    required this.name,
    required this.zoneType,
  });

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
        id: json['id'] as String,
        installationId: json['installationId'] as String,
        name: json['name'] as String,
        zoneType: json['zoneType'] as String?,
      );
}

class Gateway {
  final String id;
  final String installationId;
  final String name;
  final String connectivityType;
  final String status;
  final DateTime? lastSeenAt;

  const Gateway({
    required this.id,
    required this.installationId,
    required this.name,
    required this.connectivityType,
    required this.status,
    required this.lastSeenAt,
  });

  factory Gateway.fromJson(Map<String, dynamic> json) {
    final lastSeenRaw = json['lastSeenAt'] as String?;
    return Gateway(
      id: json['id'] as String,
      installationId: json['installationId'] as String,
      name: json['name'] as String,
      connectivityType: json['connectivityType'] as String,
      status: json['status'] as String,
      lastSeenAt: lastSeenRaw == null ? null : DateTime.parse(lastSeenRaw),
    );
  }
}

/// Credencial de un gateway (SECURITY.md §6): el secreto solo llega en la
/// respuesta de creación o rotación, nunca se puede recuperar después — el
/// llamador es responsable de mostrarlo una única vez y avisar de que no
/// se volverá a ver.
class GatewayCredential {
  final Gateway gateway;
  final String credentialUsername;
  final String credentialSecret;

  const GatewayCredential({
    required this.gateway,
    required this.credentialUsername,
    required this.credentialSecret,
  });

  factory GatewayCredential.fromJson(Map<String, dynamic> json) => GatewayCredential(
        gateway: Gateway.fromJson(json),
        credentialUsername: json['credentialUsername'] as String,
        credentialSecret: json['credentialSecret'] as String,
      );
}

class Device {
  final String id;
  final String zoneId;
  final String name;
  final String status;
  final DateTime? lastSeenAt;

  const Device({
    required this.id,
    required this.zoneId,
    required this.name,
    required this.status,
    required this.lastSeenAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    final lastSeenRaw = json['lastSeenAt'] as String?;
    return Device(
      id: json['id'] as String,
      zoneId: json['zoneId'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      lastSeenAt: lastSeenRaw == null ? null : DateTime.parse(lastSeenRaw),
    );
  }
}

class Sensor {
  final String id;
  final String externalIdentifier;
  final String? label;

  const Sensor({required this.id, required this.externalIdentifier, required this.label});

  factory Sensor.fromJson(Map<String, dynamic> json) => Sensor(
        id: json['id'] as String,
        externalIdentifier: json['externalIdentifier'] as String,
        label: json['label'] as String?,
      );
}

class Channel {
  final String id;
  final String channelTypeCode;
  final double? alertThresholdMin;
  final double? alertThresholdMax;

  const Channel({
    required this.id,
    required this.channelTypeCode,
    required this.alertThresholdMin,
    required this.alertThresholdMax,
  });

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
        id: json['id'] as String,
        channelTypeCode: json['channelTypeCode'] as String,
        alertThresholdMin: (json['alertThresholdMin'] as num?)?.toDouble(),
        alertThresholdMax: (json['alertThresholdMax'] as num?)?.toDouble(),
      );
}
