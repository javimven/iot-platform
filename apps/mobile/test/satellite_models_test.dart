import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/parcels/data/parcel_models.dart';
import 'package:iot_platform_app/features/satellite/data/satellite_models.dart';
import 'package:latlong2/latlong.dart';

/// BACKLOG.md #36. El riesgo de verdad aquí es el orden de las coordenadas:
/// GeoJSON escribe `[longitud, latitud]` y el mapa usa `LatLng(lat, lon)`.
/// Cambiarlas de sitio no da error, solo pone la parcela en otro continente.
void main() {
  const parcelaJson = {
    'id': 'parcela-1',
    'installationId': 'finca-1',
    'name': 'La Vega',
    'notes': null,
    'geometry': {
      'type': 'MultiPolygon',
      'coordinates': [
        [
          [
            [-0.5, 39.5],
            [-0.499, 39.5],
            [-0.499, 39.501],
            [-0.5, 39.501],
            [-0.5, 39.5],
          ],
        ],
      ],
    },
    'areaM2': 9549.5,
    'bbox': [-0.5, 39.5, -0.499, 39.501],
    'geometryVersion': 2,
  };

  group('Parcel', () {
    test('lee el contorno respetando el orden de GeoJSON, no al revés', () {
      final parcela = Parcel.fromJson(parcelaJson);
      final primerVertice = parcela.contorno.anillosExteriores.first.first;

      // Valencia: latitud ~39,5 y longitud ~-0,5. Si se invirtieran, esto
      // caería en mitad del océano Índico.
      expect(primerVertice.latitude, 39.5);
      expect(primerVertice.longitude, -0.5);
    });

    test('un Polygon suelto se lee igual que un MultiPolygon de un recinto', () {
      final json = Map<String, dynamic>.from(parcelaJson);
      json['geometry'] = {
        'type': 'Polygon',
        'coordinates': (parcelaJson['geometry'] as Map)['coordinates']![0],
      };

      final parcela = Parcel.fromJson(json);
      expect(parcela.contorno.anillosExteriores, hasLength(1));
      expect(parcela.contorno.anillosExteriores.first.first.latitude, 39.5);
    });

    test('la ida y vuelta a GeoJSON conserva las coordenadas', () {
      final parcela = Parcel.fromJson(parcelaJson);
      final json = parcela.contorno.toGeoJson();

      expect(json['type'], 'MultiPolygon');
      final primeraPosicion = (((json['coordinates'] as List).first as List).first as List).first;
      expect(primeraPosicion, [-0.5, 39.5]); // [lon, lat], como manda el estándar
    });

    test('cierra el anillo al enviarlo si el dibujo quedó abierto', () {
      const abierto = ContornoParcela([
        [
          [LatLng(39.5, -0.5), LatLng(39.5, -0.499), LatLng(39.501, -0.499)],
        ],
      ]);

      final anillo = (((abierto.toGeoJson()['coordinates'] as List).first as List).first as List);
      expect(anillo, hasLength(4));
      expect(anillo.first, anillo.last);
    });

    test('da la superficie en hectáreas y el centro para encuadrar el mapa', () {
      final parcela = Parcel.fromJson(parcelaJson);

      expect(parcela.areaHa, closeTo(0.95, 0.01));
      expect(parcela.centro.latitude, closeTo(39.5005, 0.0001));
      expect(parcela.centro.longitude, closeTo(-0.4995, 0.0001));
    });

    test('estima cuántos píxeles de Sentinel-2 caben: avisa si son pocos', () {
      final parcela = Parcel.fromJson(parcelaJson);

      // ~9550 m² entre 100 m² por píxel: unos 95. Con muchos menos, la media
      // mezclaría lo de dentro con lo de fuera.
      expect(parcela.pixelesAproximados, 95);
    });
  });

  group('ObservacionSatelite', () {
    const observacionJson = {
      'observationId': 'obs-1',
      'acquisitionTime': '2026-09-15T10:42:19.000Z',
      'provider': 'copernicus',
      'collection': 'sentinel-2-l2a',
      'platform': 'sentinel-2b',
      'processingVersion': 'ndvi-s2-v1',
      'parcelGeometryVersion': 1,
      'status': 'ready',
      'quality': {
        'status': 'good',
        'validPixelFraction': 0.9234,
        'validPixelPercent': 92,
        'sceneCloudCover': 0.05,
      },
      'metrics': {
        'ndvi': {
          'mean': 0.63,
          'median': 0.66,
          'min': 0.12,
          'max': 0.84,
          'stdDev': 0.09,
          'p10': 0.4,
          'p90': 0.8,
        },
      },
      'assets': [
        {'assetId': 'asset-1', 'assetType': 'ndvi_preview', 'mediaType': 'image/png'},
        {'assetId': 'asset-2', 'assetType': 'ndvi_raster', 'mediaType': 'image/tiff'},
      ],
    };

    test('lee la métrica por su código, para que añadir otra no rompa nada', () {
      final observacion = ObservacionSatelite.fromJson(observacionJson);

      expect(observacion.ndvi?.mean, 0.63);
      expect(observacion.ndvi?.median, 0.66);
      expect(observacion.metricas.containsKey('ndre'), isFalse);
    });

    test('la calidad viene con el porcentaje ya redondeado por el backend', () {
      final observacion = ObservacionSatelite.fromJson(observacionJson);

      expect(observacion.calidad.validPixelPercent, 92);
      expect(observacion.calidad.esFiable, isTrue);
    });

    test('distingue cuál de los archivos sirve para pintar el mapa', () {
      final observacion = ObservacionSatelite.fromJson(observacionJson);
      final paraPintar = observacion.assets.where((a) => a.esImagenParaPintar).toList();

      expect(paraPintar, hasLength(1));
      expect(paraPintar.first.mediaType, 'image/png'); // el GeoTIFF no se pinta
    });

    test('una observación descartada se reconoce como tal', () {
      final json = Map<String, dynamic>.from(observacionJson);
      json['status'] = 'rejected_quality';
      json['quality'] = {
        'status': 'rejected',
        'validPixelFraction': 0.2,
        'validPixelPercent': 20,
        'sceneCloudCover': 0.9,
      };
      json['metrics'] = <String, dynamic>{};

      final observacion = ObservacionSatelite.fromJson(json);
      expect(observacion.fueDescartada, isTrue);
      expect(observacion.ndvi, isNull); // sin métrica: no hay nada que enseñar
    });
  });

  group('PuntoSatelite', () {
    test('usa los mismos nombres que el histórico de telemetría', () {
      final punto = PuntoSatelite.fromJson(const {
        'tsOrigin': '2026-09-15T10:42:19.000Z',
        'value': 0.63,
        'median': 0.66,
        'observationId': 'obs-1',
        'qualityStatus': 'partial',
      });

      expect(punto.tsOrigin.toUtc().hour, 10);
      expect(punto.value, 0.63);
      expect(punto.esFiable, isFalse); // parcial: se pinta, pero atenuado
    });
  });
}
