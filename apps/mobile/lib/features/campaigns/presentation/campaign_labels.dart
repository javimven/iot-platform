import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../data/activity_models.dart';

/// Cómo se dice en la app lo que la API guarda en inglés. En un sitio: las
/// pantallas no traducen códigos a mano.

const etiquetasDeTipo = {
  'irrigation': 'Riego',
  'fertilization': 'Fertilización',
  'phytosanitary': 'Tratamiento fitosanitario',
  'field_work': 'Labor agrícola',
  'harvest': 'Recolección',
  'observation': 'Observación',
  'sowing': 'Siembra o plantación',
  'other': 'Otra actividad',
};

const iconosDeTipo = {
  'irrigation': Icons.water_drop_outlined,
  'fertilization': Icons.science_outlined,
  'phytosanitary': Icons.shield_outlined,
  'field_work': Icons.agriculture_outlined,
  'harvest': Icons.shopping_basket_outlined,
  'observation': Icons.visibility_outlined,
  'sowing': Icons.grass_outlined,
  'other': Icons.edit_note_outlined,
};

String etiquetaDeTipo(String tipo) => etiquetasDeTipo[tipo] ?? tipo;
IconData iconoDeTipo(String tipo) => iconosDeTipo[tipo] ?? Icons.edit_note_outlined;

const unidadesDeRiego = {'m3_ha': 'm³/ha', 'm3': 'm³', 'l': 'litros'};

const unidadesDeDosis = {
  'kg_ha': 'kg/ha',
  'l_ha': 'l/ha',
  't_ha': 't/ha',
  'm3_ha': 'm³/ha',
  'kg': 'kg',
  'l': 'l',
  't': 't',
  'm3': 'm³',
};

const unidadesDeDosisFitosanitaria = {
  'l_ha': 'l/ha',
  'kg_ha': 'kg/ha',
  'l_hl': 'l/hl',
  'kg_hl': 'kg/hl',
};

const unidadesDeCosecha = {'kg': 'kg', 't': 't', 'units': 'unidades'};

const sistemasDeRiego = {
  'drip': 'Goteo',
  'micro_sprinkler': 'Microaspersión',
  'sprinkler_fixed': 'Aspersión fija',
  'sprinkler_mobile': 'Aspersión móvil',
  'fogging': 'Nebulización',
  'surface': 'Superficie o gravedad',
  'hydroponic_open': 'Hidroponía a solución perdida',
  'hydroponic_recirculating': 'Hidroponía con recirculación',
};

const tiposDeFertilizacion = {
  'base': 'Abonado de fondo',
  'top_dressing': 'Abonado de cobertera',
  'amendment': 'Enmienda',
  'other': 'Otro',
};

const materialesFertilizantes = {
  'fertilizer_product': 'Producto fertilizante',
  'solid_manure': 'Estiércol sólido',
  'slurry': 'Purín',
  'sewage_sludge': 'Lodo de depuradora',
  'compost_digestate': 'Compost o digestato',
  'other_waste': 'Otro residuo valorizable',
  'other': 'Otro material',
};

const metodosDeAplicacion = {
  'broadcast': 'A voleo',
  'localized': 'Localizada',
  'fertigation': 'Fertirrigación',
  'foliar': 'Foliar',
  'injection': 'Inyección',
  'other': 'Otra',
};

const categoriasDeProblema = {
  'weeds': 'Malas hierbas',
  'diseases': 'Enfermedades',
  'arthropods': 'Insectos y ácaros',
  'growth_regulators': 'Reguladores y otros',
  'other': 'Otro',
};

const eficacias = {'good': 'Buena', 'fair': 'Regular', 'poor': 'Mala'};

const tiposDeLabor = {
  'soil_preparation': 'Preparación del terreno',
  'tillage': 'Laboreo',
  'pruning': 'Poda',
  'clearing': 'Desbroce',
  'mowing': 'Siega',
  'shredding': 'Triturado',
  'thinning': 'Aclareo',
  'grafting': 'Injerto',
  'cover_management': 'Manejo de la cubierta',
  'mechanical_control': 'Control mecánico',
  'maintenance': 'Mantenimiento',
  'other': 'Otra labor',
};

/// Estados del cultivo en palabras. Por dentro son las fases principales de la
/// escala BBCH; el agricultor nunca ve el número. Los códigos exactos por
/// cultivo llegarán con el catálogo oficial (ADR-0014), así que de momento se
/// guarda solo el nombre.
const estadosFenologicos = [
  'Brotación o germinación',
  'Desarrollo de hojas',
  'Formación de brotes laterales',
  'Crecimiento del tallo',
  'Desarrollo de partes cosechables',
  'Aparición del órgano floral',
  'Floración',
  'Formación del fruto',
  'Maduración',
  'Senescencia',
];

final _numero = NumberFormat.decimalPattern('es_ES');
final _numeroConDecimal = NumberFormat('#,##0.##', 'es_ES');

String cifra(num valor) => _numero.format(valor);
String cifraCorta(num valor) => _numeroConDecimal.format(valor);
String superficie(double ha) => '${cifraCorta(ha)} ha';

/// "Hoy", "Ayer" o "18 sep" — cómo se agrupa la línea de tiempo.
String diaRelativo(DateTime fecha, {DateTime? hoy}) {
  final referencia = hoy ?? DateTime.now();
  final dias = DateTime(referencia.year, referencia.month, referencia.day)
      .difference(DateTime(fecha.year, fecha.month, fecha.day))
      .inDays;
  if (dias == 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  if (fecha.year == referencia.year) return DateFormat('d MMM', 'es_ES').format(fecha);
  return DateFormat('d MMM yyyy', 'es_ES').format(fecha);
}

String fechaLarga(DateTime fecha) => DateFormat('d MMMM yyyy', 'es_ES').format(fecha);
String fechaCorta(DateTime fecha) => DateFormat('dd/MM/yyyy').format(fecha);

/// Lo que se lee bajo el título de una actividad en la línea de tiempo: la
/// cifra que la resume. Sin inventar nada: si no se anotó, no sale.
String? resumenDeActividad(Actividad actividad) {
  final detalle = actividad.detalle;
  if (detalle == null) return null;
  switch (actividad.type) {
    case 'irrigation':
      final cantidad = detalle['amount'] as num?;
      final unidad = unidadesDeRiego[detalle['amountUnit']] ?? '';
      return cantidad == null ? null : '${cifraCorta(cantidad)} $unidad';
    case 'fertilization':
      final producto =
          detalle['productName'] as String? ?? materialesFertilizantes[detalle['materialType']];
      final dosis = detalle['dose'] as num?;
      final unidad = unidadesDeDosis[detalle['doseUnit']] ?? '';
      final cantidad = dosis == null ? null : '${cifraCorta(dosis)} $unidad';
      return [producto, cantidad].whereType<String>().join(' · ');
    case 'phytosanitary':
      final productos = actividad.productos.map((p) => p['productName'] as String).toList();
      final problema =
          detalle['problem'] as String? ?? categoriasDeProblema[detalle['problemCategory']];
      return [productos.join(' + '), problema]
          .whereType<String>()
          .where((t) => t.isNotEmpty)
          .join(' · ');
    case 'harvest':
      final cantidad = detalle['quantity'] as num?;
      final unidad = unidadesDeCosecha[detalle['quantityUnit']] ?? '';
      return cantidad == null ? null : '${cifraCorta(cantidad)} $unidad';
    case 'field_work':
      return tiposDeLabor[detalle['workType']];
    default:
      return null;
  }
}

/// El mensaje del backend tal cual (va en `title`, RFC 7807), que ya viene en
/// español y explica el motivo. `toString()` añadiría el código y el tipo.
String mensajeDeError(Object error) {
  if (error is ApiException) {
    if (error.errors.isNotEmpty) {
      return error.errors.map((e) => e.message).join('\n');
    }
    return error.detail ?? error.title;
  }
  return '$error';
}

/// El backend protege el módulo con `FeatureGuard`: una organización sin
/// `campaigns` recibe 403 con ese título.
bool esModuloNoContratado(Object error) =>
    error is ApiException && error.status == 403 && error.title.startsWith('Feature not enabled');
