/// Espejo de `Reading` (OPENAPI.yaml) — histórico de un canal
/// (`GET /channels/:channelId/readings`, FUNCTIONAL_REQUIREMENTS.md §12).
/// `min`/`max` solo llegan si `granularity != raw` y el canal es de tipo
/// media (ReadingsService, backend) — ausentes en canales de tipo suma/conteo.
class HistoryPoint {
  final DateTime tsOrigin;
  final double value;
  final double? min;
  final double? max;

  const HistoryPoint({
    required this.tsOrigin,
    required this.value,
    required this.min,
    required this.max,
  });

  factory HistoryPoint.fromJson(Map<String, dynamic> json) => HistoryPoint(
        tsOrigin: DateTime.parse(json['tsOrigin'] as String),
        value: (json['value'] as num).toDouble(),
        min: (json['min'] as num?)?.toDouble(),
        max: (json['max'] as num?)?.toDouble(),
      );
}
