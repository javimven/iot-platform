/// Campañas (BACKLOG.md #60, ADR-0012). Espejo de lo que devuelve la API.
///
/// Las fechas de la campaña y de las actividades son **fechas sin hora**
/// (`2026-02-03`), y así se tratan aquí: un `DateTime` a medianoche local, sin
/// pasar nunca por UTC. Una fecha del campo convertida a instante salía un día
/// antes en cualquier huso al oeste de Greenwich.
DateTime leerFecha(String texto) {
  final partes = texto.split('-').map(int.parse).toList();
  return DateTime(partes[0], partes[1], partes[2]);
}

DateTime? leerFechaONula(Object? texto) => texto is String ? leerFecha(texto) : null;

/// `2026-02-03`, que es lo que espera la API.
String escribirFecha(DateTime fecha) =>
    '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-'
    '${fecha.day.toString().padLeft(2, '0')}';

double? _numero(Object? valor) => (valor as num?)?.toDouble();

/// Un cultivo del catálogo de la plataforma.
class CultivoCatalogo {
  const CultivoCatalogo({required this.id, required this.name, required this.category});

  final String id;
  final String name;

  /// woody | herbaceous | horticultural | forage | other
  final String category;

  factory CultivoCatalogo.fromJson(Map<String, dynamic> json) => CultivoCatalogo(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
      );
}

class ParcelaDeUnidad {
  const ParcelaDeUnidad({
    required this.parcelId,
    required this.name,
    required this.parcelAreaHa,
    required this.areaHa,
    required this.effectiveAreaHa,
    required this.deleted,
  });

  final String parcelId;
  final String name;
  final double parcelAreaHa;

  /// Lo declarado; nulo = la parcela entera.
  final double? areaHa;
  final double effectiveAreaHa;

  /// La parcela se borró después; sigue en la campaña por su historia.
  final bool deleted;

  factory ParcelaDeUnidad.fromJson(Map<String, dynamic> json) => ParcelaDeUnidad(
        parcelId: json['parcelId'] as String,
        name: json['name'] as String,
        parcelAreaHa: _numero(json['parcelAreaHa'])!,
        areaHa: _numero(json['areaHa']),
        effectiveAreaHa: _numero(json['effectiveAreaHa'])!,
        deleted: json['deleted'] as bool? ?? false,
      );
}

class UnidadDeCultivo {
  const UnidadDeCultivo({
    required this.id,
    required this.cropId,
    required this.cropName,
    required this.variety,
    required this.waterRegime,
    required this.growingEnvironment,
    required this.productionSystem,
    required this.areaHa,
    required this.effectiveAreaHa,
    required this.expectedYieldKgHa,
    required this.parcels,
  });

  final String id;
  final String? cropId;
  final String cropName;
  final String? variety;
  final String? waterRegime;
  final String? growingEnvironment;
  final String? productionSystem;
  final double? areaHa;
  final double effectiveAreaHa;
  final double? expectedYieldKgHa;
  final List<ParcelaDeUnidad> parcels;

  /// "Aguacate Hass".
  String get nombre => variety == null || variety!.isEmpty ? cropName : '$cropName $variety';

  factory UnidadDeCultivo.fromJson(Map<String, dynamic> json) => UnidadDeCultivo(
        id: json['id'] as String,
        cropId: json['cropId'] as String?,
        cropName: json['cropName'] as String,
        variety: json['variety'] as String?,
        waterRegime: json['waterRegime'] as String?,
        growingEnvironment: json['growingEnvironment'] as String?,
        productionSystem: json['productionSystem'] as String?,
        areaHa: _numero(json['areaHa']),
        effectiveAreaHa: _numero(json['effectiveAreaHa'])!,
        expectedYieldKgHa: _numero(json['expectedYieldKgHa']),
        parcels: (json['parcels'] as List<dynamic>? ?? const [])
            .map((e) => ParcelaDeUnidad.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class UltimaActividad {
  const UltimaActividad({required this.type, required this.date});

  final String type;
  final DateTime date;

  factory UltimaActividad.fromJson(Map<String, dynamic> json) =>
      UltimaActividad(type: json['type'] as String, date: leerFecha(json['date'] as String));
}

/// Una campaña tal como sale en el listado y en la cabecera de su ficha.
class CampanaResumida {
  const CampanaResumida({
    required this.id,
    required this.name,
    required this.status,
    required this.managementMode,
    required this.installationId,
    required this.installationName,
    required this.startDate,
    required this.expectedEndDate,
    required this.endDate,
    required this.crops,
    required this.parcelCount,
    required this.areaHa,
    required this.lastActivity,
  });

  final String id;
  final String name;

  /// draft | active | closed | archived
  final String status;

  /// simple | complete
  final String managementMode;
  final String installationId;
  final String installationName;
  final DateTime startDate;
  final DateTime? expectedEndDate;
  final DateTime? endDate;
  final List<String> crops;
  final int parcelCount;
  final double areaHa;
  final UltimaActividad? lastActivity;

  bool get estaCerrada => status == 'closed' || status == 'archived';
  bool get esCompleta => managementMode == 'complete';

  factory CampanaResumida.fromJson(Map<String, dynamic> json) {
    final finca = json['installation'] as Map<String, dynamic>;
    return CampanaResumida(
      id: json['id'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
      managementMode: json['managementMode'] as String,
      installationId: finca['id'] as String,
      installationName: finca['name'] as String,
      startDate: leerFecha(json['startDate'] as String),
      expectedEndDate: leerFechaONula(json['expectedEndDate']),
      endDate: leerFechaONula(json['endDate']),
      crops: (json['crops'] as List<dynamic>? ?? const []).cast<String>(),
      parcelCount: json['parcelCount'] as int,
      areaHa: _numero(json['areaHa'])!,
      lastActivity: json['lastActivity'] == null
          ? null
          : UltimaActividad.fromJson(json['lastActivity'] as Map<String, dynamic>),
    );
  }
}

/// La ficha completa: la cabecera más sus unidades de cultivo.
class Campana {
  const Campana({
    required this.resumen,
    required this.notes,
    required this.notebookProfile,
    required this.declaredProductionKg,
    required this.closingNotes,
    required this.cropUnits,
  });

  final CampanaResumida resumen;
  final String? notes;
  final Map<String, dynamic> notebookProfile;
  final double? declaredProductionKg;
  final String? closingNotes;
  final List<UnidadDeCultivo> cropUnits;

  String get id => resumen.id;

  /// Cada parcela de cada unidad, que es lo que se marca al registrar una
  /// actividad. Una parcela con dos cultivos sale dos veces.
  List<({UnidadDeCultivo unidad, ParcelaDeUnidad parcela})> get parcelas => [
        for (final unidad in cropUnits)
          for (final parcela in unidad.parcels.where((p) => !p.deleted))
            (unidad: unidad, parcela: parcela),
      ];

  factory Campana.fromJson(Map<String, dynamic> json) => Campana(
        resumen: CampanaResumida.fromJson(json),
        notes: json['notes'] as String?,
        notebookProfile: (json['notebookProfile'] as Map<String, dynamic>?) ?? const {},
        declaredProductionKg: _numero(json['declaredProductionKg']),
        closingNotes: json['closingNotes'] as String?,
        cropUnits: (json['cropUnits'] as List<dynamic>? ?? const [])
            .map((e) => UnidadDeCultivo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Lo que se manda al crear una campaña.
class NuevaCampana {
  const NuevaCampana({
    required this.managementMode,
    required this.startDate,
    required this.parcelIds,
    this.cropId,
    this.cropName,
    this.variety,
    this.expectedEndDate,
    this.name,
    this.notes,
  });

  final String managementMode;
  final DateTime startDate;
  final List<String> parcelIds;
  final String? cropId;
  final String? cropName;
  final String? variety;
  final DateTime? expectedEndDate;
  final String? name;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'managementMode': managementMode,
        'startDate': escribirFecha(startDate),
        if (expectedEndDate != null) 'expectedEndDate': escribirFecha(expectedEndDate!),
        if (name != null && name!.trim().isNotEmpty) 'name': name!.trim(),
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
        'cropUnits': [
          {
            if (cropId != null) 'cropId': cropId,
            if (cropName != null && cropName!.trim().isNotEmpty) 'cropName': cropName!.trim(),
            if (variety != null && variety!.trim().isNotEmpty) 'variety': variety!.trim(),
            'parcels': [
              for (final id in parcelIds) {'parcelId': id},
            ],
          },
        ],
      };
}

/// El resumen de una campaña. Un apartado nulo es que no hay actividades de
/// ese tipo: no se enseña un cero que parezca una medida.
class ResumenCampana {
  const ResumenCampana({
    required this.areaHa,
    required this.activityCount,
    required this.riego,
    required this.abonado,
    required this.tratamientos,
    required this.cosecha,
    required this.labores,
    required this.observaciones,
    required this.unidades,
  });

  final double areaHa;
  final int activityCount;
  final ({int count, double volumeM3, double? volumeM3PerHa, int withoutVolume})? riego;
  final ({
    int count,
    double? nKgHa,
    double? p2o5KgHa,
    double? k2oKgHa,
    int withoutComposition,
  })? abonado;
  final ({int count, int distinctProducts})? tratamientos;
  final ({
    int count,
    double quantityKg,
    double? yieldKgHa,
    double? expectedYieldKgHa,
    int withoutKg,
  })? cosecha;
  final int? labores;
  final int? observaciones;
  final List<({String cropName, double areaHa, double? harvestKg, double? yieldKgHa})> unidades;

  bool get vacio => activityCount == 0;

  factory ResumenCampana.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? seccion(String clave) => json[clave] as Map<String, dynamic>?;
    final riego = seccion('irrigation');
    final abonado = seccion('fertilization');
    final tratamientos = seccion('phytosanitary');
    final cosecha = seccion('harvest');
    return ResumenCampana(
      areaHa: _numero(json['areaHa'])!,
      activityCount: json['activityCount'] as int,
      riego: riego == null
          ? null
          : (
              count: riego['count'] as int,
              volumeM3: _numero(riego['volumeM3'])!,
              volumeM3PerHa: _numero(riego['volumeM3PerHa']),
              withoutVolume: riego['withoutVolume'] as int,
            ),
      abonado: abonado == null
          ? null
          : (
              count: abonado['count'] as int,
              nKgHa: _numero(abonado['nKgHa']),
              p2o5KgHa: _numero(abonado['p2o5KgHa']),
              k2oKgHa: _numero(abonado['k2oKgHa']),
              withoutComposition: abonado['withoutComposition'] as int,
            ),
      tratamientos: tratamientos == null
          ? null
          : (
              count: tratamientos['count'] as int,
              distinctProducts: tratamientos['distinctProducts'] as int,
            ),
      cosecha: cosecha == null
          ? null
          : (
              count: cosecha['count'] as int,
              quantityKg: _numero(cosecha['quantityKg'])!,
              yieldKgHa: _numero(cosecha['yieldKgHa']),
              expectedYieldKgHa: _numero(cosecha['expectedYieldKgHa']),
              withoutKg: cosecha['withoutKg'] as int,
            ),
      labores: (seccion('fieldWork'))?['count'] as int?,
      observaciones: (seccion('observations'))?['count'] as int?,
      unidades: (json['cropUnits'] as List<dynamic>? ?? const []).map((e) {
        final u = e as Map<String, dynamic>;
        return (
          cropName: u['cropName'] as String,
          areaHa: _numero(u['areaHa'])!,
          harvestKg: _numero(u['harvestKg']),
          yieldKgHa: _numero(u['yieldKgHa']),
        );
      }).toList(),
    );
  }
}
