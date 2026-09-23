/// Fotos y documentos del cuaderno (BACKLOG.md #60, fase 6). Espejo de lo que
/// devuelve la API.
class DocumentoDelCuaderno {
  const DocumentoDelCuaderno({
    required this.id,
    required this.documentType,
    required this.filename,
    required this.mediaType,
    required this.byteSize,
    required this.campaignId,
    required this.activityId,
    required this.createdAt,
    required this.url,
    required this.urlExpiresAt,
    this.title,
  });

  final String id;

  /// photo | invoice | delivery_note | analysis | …
  final String documentType;
  final String filename;
  final String mediaType;
  final int byteSize;
  final String campaignId;

  /// Nulo = está colgado de la campaña, no de una actividad.
  final String? activityId;
  final DateTime createdAt;

  /// Enlace firmado que **caduca**: para verlo más tarde hay que volver a
  /// pedir la lista, no guardarlo.
  final String url;
  final DateTime urlExpiresAt;
  final String? title;

  bool get esImagen => mediaType.startsWith('image/');

  /// Lo que se enseña como nombre: el título si lo pusieron, o el fichero.
  String get nombre => title?.trim().isNotEmpty == true ? title!.trim() : filename;

  factory DocumentoDelCuaderno.fromJson(Map<String, dynamic> json) => DocumentoDelCuaderno(
        id: json['id'] as String,
        documentType: json['documentType'] as String,
        filename: json['filename'] as String,
        mediaType: json['mediaType'] as String,
        byteSize: json['byteSize'] as int,
        campaignId: json['campaignId'] as String,
        activityId: json['activityId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        url: json['url'] as String,
        urlExpiresAt: DateTime.parse(json['urlExpiresAt'] as String).toLocal(),
        title: json['title'] as String?,
      );
}

/// Cómo se dice cada tipo de documento en la app.
const tiposDeDocumento = {
  'photo': 'Foto',
  'invoice': 'Factura',
  'contract': 'Contrato',
  'inspection_certificate': 'Certificado de inspección',
  'container_management': 'Gestión de envases',
  'analysis': 'Analítica',
  'advice': 'Asesoramiento',
  'delivery_note': 'Albarán',
  'fertilization_plan': 'Plan de abonado',
  'other': 'Otro documento',
};

String etiquetaDeDocumento(String tipo) => tiposDeDocumento[tipo] ?? 'Documento';

/// "2,4 MB" o "840 kB": el tamaño como lo lee una persona.
String tamanoLegible(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} kB';
  final megas = bytes / (1024 * 1024);
  return '${megas.toStringAsFixed(megas < 10 ? 1 : 0).replaceAll('.', ',')} MB';
}
