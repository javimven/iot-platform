import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Un sitio que propone el buscador: un pueblo, una calle, un portal, un
/// punto kilométrico, un código postal…
class LugarSugerido {
  const LugarSugerido({
    required this.id,
    required this.tipo,
    required this.texto,
    this.municipio,
    this.provincia,
    this.portal,
    this.posicion,
  });

  final String id;

  /// Tipo tal cual lo da CartoCiudad (`poblacion`, `Municipio`, `callejero`,
  /// `portal`, `Codpost`…). Hace falta para pedir sus coordenadas.
  final String tipo;
  final String texto;
  final String? municipio;
  final String? provincia;
  final String? portal;

  /// Algunos tipos (portales, puntos kilométricos) ya traen coordenadas en la
  /// sugerencia; el resto hay que pedirlas aparte.
  final LatLng? posicion;

  factory LugarSugerido.fromJson(Map<String, dynamic> json) {
    return LugarSugerido(
      id: '${json['id']}',
      tipo: '${json['type']}',
      texto: '${json['address'] ?? ''}',
      municipio: json['muni'] as String?,
      provincia: json['province'] as String?,
      portal: json['portalNumber'] == null ? null : '${json['portalNumber']}',
      posicion: posicionDeCartoCiudad(json),
    );
  }

  /// Qué es, en palabras de la gente. Tipos comprobados contra el servicio
  /// (2026-09-22); los que no se reconocen se quedan sin etiqueta antes que
  /// inventarles una.
  String? get etiquetaTipo {
    switch (tipo.toLowerCase()) {
      case 'poblacion':
        return 'Población';
      case 'municipio':
        return 'Municipio';
      case 'callejero':
        return 'Calle';
      case 'carretera':
        return 'Carretera';
      case 'portal':
        return texto.contains(' km ') ? 'Punto kilométrico' : 'Dirección';
      case 'codpost':
        return 'Código postal';
      // Montes, ríos, parajes, embalses… El texto ya dice cuál entre paréntesis.
      case 'toponimo':
      case 'ngbe':
        return 'Lugar';
      case 'refcatastral':
        return 'Referencia catastral';
      default:
        return null;
    }
  }

  /// La segunda línea de un resultado: dónde cae, si no lo dice ya el texto.
  String? get detalle {
    final partes = [
      if (etiquetaTipo != null) etiquetaTipo!,
      if (provincia != null && provincia!.isNotEmpty) provincia!,
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  /// A qué zoom se enseña: un municipio entero no cabe al zoom de un portal.
  double get zoom {
    switch (tipo.toLowerCase()) {
      case 'municipio':
      case 'carretera':
        return 13;
      case 'codpost':
        return 14;
      case 'poblacion':
      case 'toponimo':
      case 'ngbe':
        return 15;
      case 'callejero':
        return 17;
      case 'portal':
      case 'refcatastral':
        return 18;
      default:
        return 15;
    }
  }
}

/// CartoCiudad marca "sin coordenadas" con `0, 0`, no con un nulo: las
/// sugerencias de pueblos y calles vienen así (comprobado el 2026-09-22).
LatLng? posicionDeCartoCiudad(Map<String, dynamic> json) {
  final lat = json['lat'];
  final lng = json['lng'];
  if (lat is! num || lng is! num) return null;
  if (lat == 0 && lng == 0) return null;
  return LatLng(lat.toDouble(), lng.toDouble());
}

/// Buscador de sitios de España sobre **CartoCiudad** (IGN), el geocodificador
/// oficial: pueblos, calles, portales, puntos kilométricos, parajes, códigos
/// postales y referencias catastrales.
///
/// Por qué este y no otro: gratuito, sin clave ni cuota, cubre justo lo que
/// cubre la ortofoto (España) y sus datos son CC BY 4.0 del Sistema
/// Cartográfico Nacional. Su servidor manda `Access-Control-Allow-Origin: *`,
/// así que la web lo llama directamente.
///
/// **Cliente HTTP propio a propósito**, no el `ApiClient` de la app: aquel
/// pone el token de la sesión en cada petición, y ese token no puede salir
/// hacia un servidor que no es el nuestro. A CartoCiudad solo le llega el
/// texto que se busca.
class BuscadorDeLugares {
  BuscadorDeLugares([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://www.cartociudad.es/geocoder/api/geocoder',
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;

  /// Atribución de los datos de búsqueda (CC BY 4.0).
  static const atribucion = 'Búsqueda: CartoCiudad · CC BY 4.0 scne.es';

  Future<List<LugarSugerido>> sugerencias(String texto, {int limite = 6}) async {
    final respuesta = await _dio.get<dynamic>(
      '/candidates',
      queryParameters: {'q': texto, 'limit': limite},
    );
    final datos = respuesta.data;
    if (datos is! List) return const [];
    return datos.whereType<Map<String, dynamic>>().map(LugarSugerido.fromJson).toList();
  }

  /// Coordenadas de una sugerencia: las suyas si las trae, y si no, las de
  /// la segunda llamada (`find`). `null` si CartoCiudad no sabe situarla.
  Future<LatLng?> posicion(LugarSugerido lugar) async {
    if (lugar.posicion != null) return lugar.posicion;
    final respuesta = await _dio.get<dynamic>(
      '/find',
      queryParameters: {
        'q': lugar.texto,
        'type': lugar.tipo,
        'id': lugar.id,
        if (lugar.portal != null) 'portal': lugar.portal,
      },
    );
    final datos = respuesta.data;
    return datos is Map<String, dynamic> ? posicionDeCartoCiudad(datos) : null;
  }
}

final buscadorDeLugaresProvider = Provider<BuscadorDeLugares>((ref) => BuscadorDeLugares());
