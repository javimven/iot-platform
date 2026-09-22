/// Calidad de una observación. Va siempre pegada al valor: un NDVI de un día
/// medio nublado no se puede enseñar igual que uno de un día despejado.
class CalidadObservacion {
  /// `good`, `partial` o `rejected`.
  final String? status;
  final double? validPixelFraction;

  /// Ya redondeado por el backend: enseñar decimales aquí sería fingir una
  /// precisión que el dato no tiene.
  final int? validPixelPercent;

  /// Nubes de la escena entera. Informativo: no es la nubosidad sobre la
  /// parcela, que es lo que dice `validPixelPercent`.
  final double? sceneCloudCover;

  const CalidadObservacion({
    required this.status,
    required this.validPixelFraction,
    required this.validPixelPercent,
    required this.sceneCloudCover,
  });

  bool get esFiable => status == 'good';
  bool get esParcial => status == 'partial';

  factory CalidadObservacion.fromJson(Map<String, dynamic> json) => CalidadObservacion(
        status: json['status'] as String?,
        validPixelFraction: (json['validPixelFraction'] as num?)?.toDouble(),
        validPixelPercent: json['validPixelPercent'] as int?,
        sceneCloudCover: (json['sceneCloudCover'] as num?)?.toDouble(),
      );
}

class MetricaSatelite {
  final double mean;
  final double median;
  final double min;
  final double max;
  final double stdDev;

  const MetricaSatelite({
    required this.mean,
    required this.median,
    required this.min,
    required this.max,
    required this.stdDev,
  });

  factory MetricaSatelite.fromJson(Map<String, dynamic> json) => MetricaSatelite(
        mean: (json['mean'] as num).toDouble(),
        median: (json['median'] as num).toDouble(),
        min: (json['min'] as num).toDouble(),
        max: (json['max'] as num).toDouble(),
        stdDev: (json['stdDev'] as num).toDouble(),
      );
}

class AssetSatelite {
  final String assetId;

  /// `ndvi_raster` (GeoTIFF, el dato) o `ndvi_preview` (PNG, para pintar).
  final String assetType;
  final String mediaType;

  const AssetSatelite({
    required this.assetId,
    required this.assetType,
    required this.mediaType,
  });

  bool get esImagenParaPintar => assetType == 'ndvi_preview';

  factory AssetSatelite.fromJson(Map<String, dynamic> json) => AssetSatelite(
        assetId: json['assetId'] as String,
        assetType: json['assetType'] as String,
        mediaType: json['mediaType'] as String,
      );
}

class ObservacionSatelite {
  final String observationId;

  /// Momento de la pasada, en UTC. Es la fecha que ve el usuario y la que
  /// ordena la gráfica — nunca la de procesado.
  final DateTime acquisitionTime;
  final String provider;
  final String? platform;
  final String status;
  final CalidadObservacion calidad;
  final Map<String, MetricaSatelite> metricas;
  final List<AssetSatelite> assets;

  /// Contorno con el que se midió. Si la parcela se ha redibujado después,
  /// este dato es de otro recinto y conviene decirlo.
  final int parcelGeometryVersion;

  const ObservacionSatelite({
    required this.observationId,
    required this.acquisitionTime,
    required this.provider,
    required this.platform,
    required this.status,
    required this.calidad,
    required this.metricas,
    required this.assets,
    required this.parcelGeometryVersion,
  });

  MetricaSatelite? get ndvi => metricas['ndvi'];

  bool get fueDescartada => status == 'rejected_quality';

  factory ObservacionSatelite.fromJson(Map<String, dynamic> json) => ObservacionSatelite(
        observationId: json['observationId'] as String,
        acquisitionTime: DateTime.parse(json['acquisitionTime'] as String),
        provider: json['provider'] as String,
        platform: json['platform'] as String?,
        status: json['status'] as String,
        calidad: CalidadObservacion.fromJson(json['quality'] as Map<String, dynamic>),
        metricas: (json['metrics'] as Map<String, dynamic>? ?? {}).map(
          (codigo, valores) =>
              MapEntry(codigo, MetricaSatelite.fromJson(valores as Map<String, dynamic>)),
        ),
        assets: (json['assets'] as List<dynamic>? ?? [])
            .map((a) => AssetSatelite.fromJson(a as Map<String, dynamic>))
            .toList(),
        parcelGeometryVersion: json['parcelGeometryVersion'] as int,
      );
}

/// Punto de la serie de NDVI. Mismos nombres que el histórico de un canal de
/// telemetría (`tsOrigin`/`value`) para poder reutilizar las gráficas.
class PuntoSatelite {
  final DateTime tsOrigin;
  final double value;
  final double median;
  final String observationId;
  final String? qualityStatus;

  const PuntoSatelite({
    required this.tsOrigin,
    required this.value,
    required this.median,
    required this.observationId,
    required this.qualityStatus,
  });

  bool get esFiable => qualityStatus == 'good';

  factory PuntoSatelite.fromJson(Map<String, dynamic> json) => PuntoSatelite(
        tsOrigin: DateTime.parse(json['tsOrigin'] as String),
        value: (json['value'] as num).toDouble(),
        median: (json['median'] as num).toDouble(),
        observationId: json['observationId'] as String,
        qualityStatus: json['qualityStatus'] as String?,
      );
}

/// Enlace temporal a un archivo. El bucket es privado: esto caduca solo.
class EnlaceAsset {
  final String url;
  final DateTime expiresAt;

  const EnlaceAsset({required this.url, required this.expiresAt});

  factory EnlaceAsset.fromJson(Map<String, dynamic> json) => EnlaceAsset(
        url: json['url'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}
