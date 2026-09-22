import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/satellite/data/coordenadas.dart';
import 'package:latlong2/latlong.dart';

/// Coordenadas escritas a mano o pegadas en el buscador del mapa. Lo que se
/// fija: se aceptan las formas en que la gente las tiene a mano, y lo que no
/// son coordenadas no se lee como tales (se busca como nombre de sitio).
void main() {
  void esperar(String texto, double lat, double lng) {
    final punto = leerCoordenadas(texto);
    expect(punto, isNotNull, reason: texto);
    expect(punto!.latitude, closeTo(lat, 1e-6), reason: texto);
    expect(punto.longitude, closeTo(lng, 1e-6), reason: texto);
  }

  group('grados decimales', () {
    test('con punto, coma de separación y espacio', () {
      esperar('39.5116, -0.4536', 39.5116, -0.4536);
    });

    test('con coma decimal, como se escribe en España', () {
      esperar('39,5116 -0,4536', 39.5116, -0.4536);
      esperar('39,5116, -0,4536', 39.5116, -0.4536);
    });

    test('pegados sin espacio o con punto y coma', () {
      esperar('39.5116,-0.4536', 39.5116, -0.4536);
      esperar('39.5116;-0.4536', 39.5116, -0.4536);
      esperar('  39.5116   -0.4536  ', 39.5116, -0.4536);
    });
  });

  group('grados, minutos y segundos', () {
    test('como los copia Google Maps', () {
      esperar('39°30\'41.8"N 0°27\'13.0"W', 39.511611, -0.453611);
    });

    test('oeste también con O, y las letras mandan sobre el orden', () {
      esperar('39°30\'41.8"N 0°27\'13.0"O', 39.511611, -0.453611);
      esperar('0°27\'13.0"W 39°30\'41.8"N', 39.511611, -0.453611);
    });

    test('sur y oeste dan negativos', () {
      esperar('33°52\'S 151°12\'E', -33.866667, 151.2);
    });
  });

  group('lo que no son coordenadas', () {
    test('un nombre de sitio', () {
      expect(leerCoordenadas('Paterna'), isNull);
      expect(leerCoordenadas('calle mayor 5, 12'), isNull);
    });

    test('un código postal o una referencia catastral', () {
      expect(leerCoordenadas('46980'), isNull);
      expect(leerCoordenadas('9872023VH5797S'), isNull);
    });

    test('fuera de rango: por ejemplo, UTM del SIGPAC', () {
      expect(leerCoordenadas('716234, 4376543'), isNull);
      expect(leerCoordenadas('91, 10'), isNull);
    });

    test('vacío', () {
      expect(leerCoordenadas('   '), isNull);
    });
  });

  test('el formato corto lleva cinco decimales (un metro)', () {
    expect(formatearCoordenadas(const LatLng(39.511631135, -0.453608995)), '39.51163, -0.45361');
  });
}
