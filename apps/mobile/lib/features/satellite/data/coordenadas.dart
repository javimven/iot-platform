import 'package:latlong2/latlong.dart';

/// Lee unas coordenadas escritas a mano o pegadas de otra aplicación, en el
/// orden de siempre: **latitud primero**.
///
/// Admite lo que la gente suele tener a mano:
/// - grados decimales con punto o con coma: `39.5116, -0.4536`,
///   `39,5116 -0,4536`, `39.5116;-0.4536`;
/// - grados, minutos y segundos, como los copia Google Maps:
///   `39°30'41.8"N 0°27'13.0"W` (también `O` de oeste).
///
/// Devuelve `null` si el texto no son unas coordenadas válidas, y entonces el
/// buscador lo trata como el nombre de un sitio. No intenta adivinar: unas
/// coordenadas UTM (las del visor del SIGPAC, por ejemplo) no son grados y no
/// se leen como tales.
LatLng? leerCoordenadas(String texto) {
  final limpio = texto.trim();
  if (limpio.isEmpty) return null;
  return _leerSexagesimales(limpio) ?? _leerDecimales(limpio);
}

/// Formato corto para enseñar unas coordenadas: cinco decimales son un metro,
/// más no aporta nada al buscar una parcela.
String formatearCoordenadas(LatLng punto) =>
    '${punto.latitude.toStringAsFixed(5)}, ${punto.longitude.toStringAsFixed(5)}';

final _numero = RegExp(r'-?\d+(?:[.,]\d+)?');
final _separadores = RegExp(r'^[\s,;]*$');

LatLng? _leerDecimales(String texto) {
  final numeros = _numero.allMatches(texto).map((m) => m.group(0)!).toList();
  if (numeros.length != 2) return null;
  // Entre los dos números solo puede haber separadores: "calle 5, 12" no son
  // coordenadas aunque tenga dos números.
  if (!_separadores.hasMatch(texto.replaceAll(_numero, ''))) return null;
  return _dentroDeRango(_aDouble(numeros[0]), _aDouble(numeros[1]));
}

final _componenteSexagesimal = RegExp(
  r'''(-?\d+(?:[.,]\d+)?)\s*°\s*(?:(\d+(?:[.,]\d+)?)\s*['′]\s*)?(?:(\d+(?:[.,]\d+)?)\s*(?:"|″|''))?\s*([NSEWO])?''',
  caseSensitive: false,
);

LatLng? _leerSexagesimales(String texto) {
  if (!texto.contains('°')) return null;
  final partes = _componenteSexagesimal.allMatches(texto).toList();
  if (partes.length != 2) return null;

  double? valor(RegExpMatch m) {
    final grados = _aDouble(m.group(1)!);
    final minutos = m.group(2) == null ? 0.0 : _aDouble(m.group(2)!);
    final segundos = m.group(3) == null ? 0.0 : _aDouble(m.group(3)!);
    if (minutos >= 60 || segundos >= 60) return null;
    final absoluto = grados.abs() + minutos / 60 + segundos / 3600;
    final hemisferio = m.group(4)?.toUpperCase();
    final negativo = grados < 0 || hemisferio == 'S' || hemisferio == 'W' || hemisferio == 'O';
    return negativo ? -absoluto : absoluto;
  }

  var primera = partes[0];
  var segunda = partes[1];
  // Con hemisferios explícitos, el orden lo dicen las letras: "0°27'W 39°30'N"
  // también vale.
  final letraPrimera = primera.group(4)?.toUpperCase();
  if (letraPrimera == 'E' || letraPrimera == 'W' || letraPrimera == 'O') {
    (primera, segunda) = (segunda, primera);
  }

  final latitud = valor(primera);
  final longitud = valor(segunda);
  if (latitud == null || longitud == null) return null;
  return _dentroDeRango(latitud, longitud);
}

double _aDouble(String numero) => double.parse(numero.replaceAll(',', '.'));

LatLng? _dentroDeRango(double latitud, double longitud) {
  if (latitud.abs() > 90 || longitud.abs() > 180) return null;
  return LatLng(latitud, longitud);
}
