import 'campaign_models.dart';

/// Tipos de actividad (los mismos que el backend, ADR-0012).
const tiposDeActividad = [
  'irrigation',
  'fertilization',
  'phytosanitary',
  'field_work',
  'harvest',
  'observation',
  'sowing',
  'other',
];

/// Clave del detalle de cada tipo en la API. Observación, siembra y "otra" no
/// llevan detalle.
String? claveDelDetalle(String tipo) => const {
      'irrigation': 'irrigation',
      'fertilization': 'fertilization',
      'phytosanitary': 'phytosanitary',
      'harvest': 'harvest',
      'field_work': 'fieldWork',
    }[tipo];

class DestinoDeActividad {
  const DestinoDeActividad({
    required this.parcelId,
    required this.parcelName,
    required this.cropUnitId,
    required this.cropName,
    required this.areaHa,
    required this.effectiveAreaHa,
  });

  final String parcelId;
  final String parcelName;
  final String cropUnitId;
  final String cropName;
  final double? areaHa;
  final double effectiveAreaHa;

  factory DestinoDeActividad.fromJson(Map<String, dynamic> json) => DestinoDeActividad(
        parcelId: json['parcelId'] as String,
        parcelName: json['parcelName'] as String,
        cropUnitId: json['cropUnitId'] as String,
        cropName: json['cropName'] as String,
        areaHa: (json['areaHa'] as num?)?.toDouble(),
        effectiveAreaHa: (json['effectiveAreaHa'] as num).toDouble(),
      );
}

/// Algo que se hizo en la campaña.
///
/// El detalle va como mapa, tal cual lo da la API: es lo mismo que rellena y
/// manda el formulario (al repetir o corregir), y así no hay una segunda copia
/// en Dart de los cinco tipos de detalle del backend.
class Actividad {
  const Actividad({
    required this.id,
    required this.campaignId,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.notes,
    required this.origin,
    required this.areaHa,
    required this.targets,
    required this.detalle,
    required this.createdAt,
  });

  final String id;
  final String campaignId;
  final String type;
  final DateTime startDate;
  final DateTime endDate;
  final String? startTime;
  final String? notes;

  /// manual | repeated | sensor_suggestion
  final String origin;
  final double areaHa;
  final List<DestinoDeActividad> targets;

  /// El detalle de su tipo, o nulo si no lleva o no se rellenó.
  final Map<String, dynamic>? detalle;
  final DateTime createdAt;

  bool get esDeVariosDias => endDate.isAfter(startDate);

  /// Productos de un tratamiento.
  List<Map<String, dynamic>> get productos =>
      ((detalle?['products'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();

  factory Actividad.fromJson(Map<String, dynamic> json) {
    final tipo = json['type'] as String;
    final clave = claveDelDetalle(tipo);
    return Actividad(
      id: json['id'] as String,
      campaignId: json['campaignId'] as String,
      type: tipo,
      startDate: leerFecha(json['startDate'] as String),
      endDate: leerFecha(json['endDate'] as String),
      startTime: json['startTime'] as String?,
      notes: json['notes'] as String?,
      origin: json['origin'] as String? ?? 'manual',
      areaHa: (json['areaHa'] as num).toDouble(),
      targets: (json['targets'] as List<dynamic>)
          .map((e) => DestinoDeActividad.fromJson(e as Map<String, dynamic>))
          .toList(),
      detalle: clave == null ? null : json[clave] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
