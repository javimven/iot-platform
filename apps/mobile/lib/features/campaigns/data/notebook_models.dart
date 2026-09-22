import 'campaign_models.dart' show escribirFecha, leerFechaONula;

/// Cuaderno completo (fase 5 del #60): los catálogos de personas y equipos, y
/// la revisión de lo que falta. Espejo de lo que devuelve la API.

/// Quién trata o quién asesora. Se da de alta una vez y se elige después.
class PersonaCuaderno {
  const PersonaCuaderno({
    required this.id,
    required this.kind,
    required this.displayName,
    this.installationId,
    this.firstName,
    this.surname1,
    this.surname2,
    this.companyName,
    this.nif,
    this.ropoNumber,
    this.ropoCardType,
    this.notes,
    this.deleted = false,
  });

  final String id;

  /// own_staff | service_company | adviser
  final String kind;

  /// La persona, o la empresa si no hay persona. Lo monta el backend.
  final String displayName;

  /// Nulo = vale para todas las fincas.
  final String? installationId;
  final String? firstName;
  final String? surname1;
  final String? surname2;
  final String? companyName;
  final String? nif;
  final String? ropoNumber;
  final String? ropoCardType;
  final String? notes;
  final bool deleted;

  factory PersonaCuaderno.fromJson(Map<String, dynamic> json) => PersonaCuaderno(
        id: json['id'] as String,
        kind: json['kind'] as String,
        displayName: json['displayName'] as String? ?? '',
        installationId: json['installationId'] as String?,
        firstName: json['firstName'] as String?,
        surname1: json['surname1'] as String?,
        surname2: json['surname2'] as String?,
        companyName: json['companyName'] as String?,
        nif: json['nif'] as String?,
        ropoNumber: json['ropoNumber'] as String?,
        ropoCardType: json['ropoCardType'] as String?,
        notes: json['notes'] as String?,
        deleted: json['deleted'] as bool? ?? false,
      );

  /// Lo que se manda al crear o cambiar. Una cadena vacía borra ese dato, así
  /// que solo van las claves que el formulario ha tocado.
  static Map<String, dynamic> cuerpo({
    String? kind,
    String? installationId,
    bool fincaTocada = false,
    String? firstName,
    String? surname1,
    String? surname2,
    String? companyName,
    String? nif,
    String? ropoNumber,
    String? ropoCardType,
    String? notes,
  }) =>
      {
        if (kind != null) 'kind': kind,
        if (fincaTocada) 'installationId': installationId,
        if (firstName != null) 'firstName': firstName.trim(),
        if (surname1 != null) 'surname1': surname1.trim(),
        if (surname2 != null) 'surname2': surname2.trim(),
        if (companyName != null) 'companyName': companyName.trim(),
        if (nif != null) 'nif': nif.trim(),
        if (ropoNumber != null) 'ropoNumber': ropoNumber.trim(),
        if (ropoCardType != null) 'ropoCardType': ropoCardType.trim(),
        if (notes != null) 'notes': notes.trim(),
      };
}

/// Un equipo de aplicación.
class EquipoCuaderno {
  const EquipoCuaderno({
    required this.id,
    required this.description,
    required this.displayName,
    this.installationId,
    this.brand,
    this.model,
    this.romaNumber,
    this.acquiredOn,
    this.lastInspectionOn,
    this.notes,
    this.deleted = false,
  });

  final String id;
  final String description;
  final String displayName;
  final String? installationId;
  final String? brand;
  final String? model;
  final String? romaNumber;
  final DateTime? acquiredOn;
  final DateTime? lastInspectionOn;
  final String? notes;
  final bool deleted;

  factory EquipoCuaderno.fromJson(Map<String, dynamic> json) => EquipoCuaderno(
        id: json['id'] as String,
        description: json['description'] as String,
        displayName: json['displayName'] as String? ?? json['description'] as String,
        installationId: json['installationId'] as String?,
        brand: json['brand'] as String?,
        model: json['model'] as String?,
        romaNumber: json['romaNumber'] as String?,
        acquiredOn: leerFechaONula(json['acquiredOn']),
        lastInspectionOn: leerFechaONula(json['lastInspectionOn']),
        notes: json['notes'] as String?,
        deleted: json['deleted'] as bool? ?? false,
      );

  static Map<String, dynamic> cuerpo({
    String? description,
    String? installationId,
    bool fincaTocada = false,
    String? brand,
    String? model,
    String? romaNumber,
    DateTime? acquiredOn,
    DateTime? lastInspectionOn,
    String? notes,
  }) =>
      {
        if (description != null) 'description': description.trim(),
        if (fincaTocada) 'installationId': installationId,
        if (brand != null) 'brand': brand.trim(),
        if (model != null) 'model': model.trim(),
        if (romaNumber != null) 'romaNumber': romaNumber.trim(),
        if (acquiredOn != null) 'acquiredOn': escribirFecha(acquiredOn),
        if (lastInspectionOn != null) 'lastInspectionOn': escribirFecha(lastInspectionOn),
        if (notes != null) 'notes': notes.trim(),
      };
}

/// Una cosa que falta o que conviene revisar, con su fuente.
class AvisoDelCuaderno {
  const AvisoDelCuaderno({
    required this.code,
    required this.kind,
    required this.label,
    required this.why,
    required this.sourceLabel,
  });

  final String code;

  /// missing = información pendiente; warning = conviene revisarlo.
  final String kind;
  final String label;
  final String why;
  final String sourceLabel;

  bool get esFalta => kind == 'missing';

  factory AvisoDelCuaderno.fromJson(Map<String, dynamic> json) => AvisoDelCuaderno(
        code: json['code'] as String,
        kind: json['kind'] as String,
        label: json['label'] as String,
        why: json['why'] as String? ?? '',
        sourceLabel: json['sourceLabel'] as String? ?? '',
      );
}

/// Los avisos de una actividad concreta.
class ActividadConAvisos {
  const ActividadConAvisos({
    required this.activityId,
    required this.type,
    required this.date,
    required this.avisos,
  });

  final String activityId;
  final String type;
  final DateTime? date;
  final List<AvisoDelCuaderno> avisos;

  factory ActividadConAvisos.fromJson(Map<String, dynamic> json) => ActividadConAvisos(
        activityId: json['activityId'] as String,
        type: json['type'] as String,
        date: leerFechaONula(json['startDate']),
        avisos: (json['items'] as List<dynamic>? ?? const [])
            .map((e) => AvisoDelCuaderno.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// La revisión del cuaderno. Dice qué falta; **nunca dice que la campaña
/// cumple** (ADR-0013), y no bloquea nada.
class RevisionDelCuaderno {
  const RevisionDelCuaderno({
    required this.aplica,
    required this.versionDeReglas,
    required this.faltan,
    required this.avisos,
    required this.deLaCampana,
    required this.deActividades,
  });

  /// En una campaña sencilla no hay revisión.
  final bool aplica;
  final String versionDeReglas;
  final int faltan;
  final int avisos;
  final List<AvisoDelCuaderno> deLaCampana;
  final List<ActividadConAvisos> deActividades;

  bool get sinPendientes => faltan == 0 && avisos == 0;
  int get total => faltan + avisos;

  factory RevisionDelCuaderno.fromJson(Map<String, dynamic> json) => RevisionDelCuaderno(
        aplica: json['applicable'] as bool? ?? false,
        versionDeReglas: (json['rules'] as Map<String, dynamic>?)?['id'] as String? ?? '',
        faltan: json['missingCount'] as int? ?? 0,
        avisos: json['warningCount'] as int? ?? 0,
        deLaCampana: (json['campaign'] as List<dynamic>? ?? const [])
            .map((e) => AvisoDelCuaderno.fromJson(e as Map<String, dynamic>))
            .toList(),
        deActividades: (json['activities'] as List<dynamic>? ?? const [])
            .map((e) => ActividadConAvisos.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Las preguntas del cuaderno completo (`notebookProfile`). Solo lo que el
/// sistema no puede deducir: lo que ya sabe (finca, cultivo, superficie) no se
/// pregunta.
class PreguntaDelCuaderno {
  const PreguntaDelCuaderno(this.clave, this.pregunta, this.detalle);

  final String clave;
  final String pregunta;
  final String detalle;
}

const preguntasDelCuaderno = [
  PreguntaDelCuaderno(
    'usesPlantProtectionProducts',
    '¿Aplicas productos fitosanitarios?',
    'Herbicidas, fungicidas, insecticidas… propios o contratados.',
  ),
  PreguntaDelCuaderno(
    'appliesFertilizers',
    '¿Aplicas fertilizantes?',
    'Abonos minerales, estiércol, purín, compost…',
  ),
  PreguntaDelCuaderno(
    'usesFertigation',
    '¿Abonas con el riego (fertirrigación)?',
    'Si lo haces, el cuaderno pide también la calidad del agua.',
  ),
  PreguntaDelCuaderno(
    'usesValorizableWaste',
    '¿Usas residuos valorizables?',
    'Lodos de depuradora, compost o digestato de fuera de la explotación.',
  ),
  PreguntaDelCuaderno(
    'participatesInEcoSchemes',
    '¿Participas en ecorregímenes o ayudas agroambientales?',
    'Añade apartados propios al cuaderno.',
  ),
  PreguntaDelCuaderno(
    'treatedSeed',
    '¿Siembras semilla tratada?',
    'La semilla tratada se anota aparte de los tratamientos en campo.',
  ),
  PreguntaDelCuaderno(
    'postHarvestTreatments',
    '¿Haces tratamientos después de la cosecha?',
    'En almacén, transporte o postcosecha.',
  ),
];
