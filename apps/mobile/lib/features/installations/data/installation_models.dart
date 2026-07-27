/// Espejo de `Installation` (OPENAPI.yaml) — FUNCTIONAL_REQUIREMENTS.md §5.
class Installation {
  final String id;
  final String name;
  final String? locationText;
  final double? latitude;
  final double? longitude;
  final String status;

  const Installation({
    required this.id,
    required this.name,
    required this.locationText,
    required this.latitude,
    required this.longitude,
    required this.status,
  });

  factory Installation.fromJson(Map<String, dynamic> json) => Installation(
        id: json['id'] as String,
        name: json['name'] as String,
        locationText: json['locationText'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        status: json['status'] as String,
      );
}

/// Espejo de `LatestReading` — una fila por canal (Etapa 5, tabla `latest_readings`).
class LatestReading {
  final String channelId;
  final String channelTypeCode;
  final double value;
  final DateTime tsOrigin;
  final DateTime tsReceived;

  const LatestReading({
    required this.channelId,
    required this.channelTypeCode,
    required this.value,
    required this.tsOrigin,
    required this.tsReceived,
  });

  factory LatestReading.fromJson(Map<String, dynamic> json) => LatestReading(
        channelId: json['channelId'] as String,
        channelTypeCode: json['channelTypeCode'] as String? ?? '',
        value: (json['value'] as num).toDouble(),
        tsOrigin: DateTime.parse(json['tsOrigin'] as String),
        tsReceived: DateTime.parse((json['tsReceived'] as String?) ?? json['tsOrigin'] as String),
      );
}
