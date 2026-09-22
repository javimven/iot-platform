import 'package:latlong2/latlong.dart';

/// Contorno de una parcela, ya en coordenadas del mapa.
///
/// El backend habla GeoJSON (`MultiPolygon`, EPSG:4326), donde cada posición
/// es `[longitud, latitud]` — el orden **contrario** al que usa el mapa
/// (`LatLng(lat, lon)`). Confundirlos manda la parcela a otro continente, así
/// que la traducción vive aquí y en un solo sitio.
class ContornoParcela {
  /// Un recinto por cada polígono; dentro, sus anillos (el primero es el
  /// contorno exterior y el resto, huecos). La v1 dibuja uno solo, pero el
  /// formato admite varios desde el principio.
  final List<List<List<LatLng>>> recintos;

  const ContornoParcela(this.recintos);

  /// Los anillos exteriores, que es lo que se pinta.
  List<List<LatLng>> get anillosExteriores =>
      recintos.where((r) => r.isNotEmpty).map((r) => r.first).toList();

  bool get estaVacio => anillosExteriores.isEmpty;

  factory ContornoParcela.fromGeoJson(Map<String, dynamic> geometry) {
    final tipo = geometry['type'] as String?;
    final coordenadas = geometry['coordinates'] as List<dynamic>? ?? const [];

    // Un Polygon se trata como un MultiPolygon de un solo recinto: así el
    // resto del código no tiene que preguntar de qué tipo era.
    final poligonos = tipo == 'Polygon' ? [coordenadas] : coordenadas;

    return ContornoParcela(
      poligonos
          .map<List<List<LatLng>>>(
            (poligono) => (poligono as List<dynamic>)
                .map<List<LatLng>>(
                  (anillo) => (anillo as List<dynamic>)
                      .map<LatLng>((posicion) {
                        final par = posicion as List<dynamic>;
                        return LatLng(
                          (par[1] as num).toDouble(), // latitud
                          (par[0] as num).toDouble(), // longitud
                        );
                      })
                      .toList(),
                )
                .toList(),
          )
          .toList(),
    );
  }

  /// Vuelve a GeoJSON para mandarlo al backend. El anillo se cierra allí si
  /// hace falta, pero se envía cerrado igualmente: es lo que dice el estándar.
  Map<String, dynamic> toGeoJson() => {
        'type': 'MultiPolygon',
        'coordinates': recintos
            .map((recinto) => recinto
                .map((anillo) => _cerrar(anillo).map((p) => [p.longitude, p.latitude]).toList())
                .toList())
            .toList(),
      };

  static List<LatLng> _cerrar(List<LatLng> anillo) {
    if (anillo.length < 2 || anillo.first == anillo.last) return anillo;
    return [...anillo, anillo.first];
  }
}

class Parcel {
  final String id;
  final String installationId;
  final String name;
  final String? notes;
  final ContornoParcela contorno;
  final double areaM2;

  /// `[minLon, minLat, maxLon, maxLat]`.
  final List<double> bbox;

  /// Sube cada vez que se redibuja el contorno: las observaciones anteriores
  /// se calcularon sobre otro recinto.
  final int geometryVersion;

  const Parcel({
    required this.id,
    required this.installationId,
    required this.name,
    required this.notes,
    required this.contorno,
    required this.areaM2,
    required this.bbox,
    required this.geometryVersion,
  });

  /// Superficie en hectáreas, que es como se habla de una parcela en campo.
  double get areaHa => areaM2 / 10000;

  /// Centro aproximado, para encuadrar el mapa al abrirla.
  LatLng get centro => LatLng((bbox[1] + bbox[3]) / 2, (bbox[0] + bbox[2]) / 2);

  /// Píxeles de Sentinel-2 (10 m de lado) que caben, más o menos. Por debajo
  /// de unos pocos, la media mezcla lo de dentro con lo de fuera y conviene
  /// avisar en vez de dar el número como si tal cosa.
  int get pixelesAproximados => (areaM2 / 100).round();

  factory Parcel.fromJson(Map<String, dynamic> json) => Parcel(
        id: json['id'] as String,
        installationId: json['installationId'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        contorno: ContornoParcela.fromGeoJson(json['geometry'] as Map<String, dynamic>),
        areaM2: (json['areaM2'] as num).toDouble(),
        bbox: (json['bbox'] as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
        geometryVersion: json['geometryVersion'] as int,
      );
}
