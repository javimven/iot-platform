import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/satellite/data/buscador_lugares.dart';
import 'package:latlong2/latlong.dart';

/// Respuestas reales de CartoCiudad (2026-09-22), recortadas.
const _pueblo = {
  'id': '1000003934',
  'type': 'poblacion',
  'address': 'Paterna, Paterna',
  'muni': 'Paterna',
  'province': 'València/Valencia',
  'portalNumber': null,
  'lat': 0,
  'lng': 0,
};

const _puntoKilometrico = {
  'id': '460000000001',
  'type': 'portal',
  'address': 'A-7 km 330 (Manises)',
  'muni': 'Manises',
  'province': 'València/Valencia',
  'portalNumber': 330,
  'lat': 39.51030575100003,
  'lng': -0.505221466999956,
};

/// Adaptador que contesta sin red y apunta qué se ha pedido.
class _Adaptador implements HttpClientAdapter {
  _Adaptador(this.respuesta);

  final Object respuesta;
  final peticiones = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    peticiones.add(options);
    return ResponseBody.fromString(
      jsonEncode(respuesta),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('una sugerencia de pueblo no trae coordenadas: 0,0 es "no hay", no el golfo de Guinea', () {
    final lugar = LugarSugerido.fromJson(_pueblo);

    expect(lugar.posicion, isNull);
    expect(lugar.etiquetaTipo, 'Población');
    expect(lugar.detalle, 'Población · València/Valencia');
    expect(lugar.zoom, 15);
  });

  test('un punto kilométrico sí las trae, y se reconoce como tal', () {
    final lugar = LugarSugerido.fromJson(_puntoKilometrico);

    expect(lugar.posicion, const LatLng(39.51030575100003, -0.505221466999956));
    expect(lugar.etiquetaTipo, 'Punto kilométrico');
    expect(lugar.portal, '330');
  });

  test('un tipo desconocido se queda sin etiqueta antes que con una inventada', () {
    final lugar = LugarSugerido.fromJson({..._pueblo, 'type': 'algo_nuevo'});

    expect(lugar.etiquetaTipo, isNull);
    expect(lugar.detalle, 'València/Valencia');
  });

  test('sin coordenadas en la sugerencia, las pide a find con su tipo e id', () async {
    final adaptador = _Adaptador({'type': 'poblacion', 'lat': 39.5116, 'lng': -0.4536});
    final buscador = BuscadorDeLugares(Dio()..httpClientAdapter = adaptador);

    final punto = await buscador.posicion(LugarSugerido.fromJson(_pueblo));

    expect(punto, const LatLng(39.5116, -0.4536));
    final pedida = adaptador.peticiones.single;
    expect(pedida.path, '/find');
    expect(pedida.queryParameters, {
      'q': 'Paterna, Paterna',
      'type': 'poblacion',
      'id': '1000003934',
    });
  });

  test('con coordenadas en la sugerencia no hace ninguna llamada más', () async {
    final adaptador = _Adaptador(const {});
    final buscador = BuscadorDeLugares(Dio()..httpClientAdapter = adaptador);

    await buscador.posicion(LugarSugerido.fromJson(_puntoKilometrico));

    expect(adaptador.peticiones, isEmpty);
  });

  test('si find tampoco sabe situarlo, devuelve null', () async {
    final buscador = BuscadorDeLugares(Dio()..httpClientAdapter = _Adaptador({'lat': 0, 'lng': 0}));

    expect(await buscador.posicion(LugarSugerido.fromJson(_pueblo)), isNull);
  });

  test('las sugerencias se leen de la lista que devuelve candidates', () async {
    final adaptador = _Adaptador([_pueblo, _puntoKilometrico]);
    final buscador = BuscadorDeLugares(Dio()..httpClientAdapter = adaptador);

    final lugares = await buscador.sugerencias('paterna');

    expect(lugares.map((l) => l.texto), ['Paterna, Paterna', 'A-7 km 330 (Manises)']);
    expect(adaptador.peticiones.single.queryParameters, {'q': 'paterna', 'limit': 6});
  });
}
