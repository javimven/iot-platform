import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/satellite/application/ubicacion_dispositivo.dart';
import 'package:iot_platform_app/features/satellite/data/buscador_lugares.dart';
import 'package:iot_platform_app/features/satellite/presentation/parcel_map.dart';
import 'package:latlong2/latlong.dart';

/// Mapa de una parcela (BACKLOG.md #36). Lo que se fija aquí es lo que pidió
/// el usuario al usarlo: ortofoto en vez de callejero, zoom con la rueda **y**
/// con botones, nombres de sitios encima de la foto, y maneras de llegar a la
/// parcela (buscar un sitio, escribir coordenadas, ir a donde estoy).
class _UbicacionFalsa implements UbicacionDelDispositivo {
  _UbicacionFalsa({this.posicion, this.error});

  final PosicionDispositivo? posicion;
  final Object? error;

  @override
  Future<PosicionDispositivo> actual() async {
    if (error != null) throw error!;
    return posicion!;
  }
}

class _BuscadorFalso extends BuscadorDeLugares {
  _BuscadorFalso(this.lugares, {this.situacion});

  final List<LugarSugerido> lugares;
  final LatLng? situacion;
  final buscados = <String>[];

  @override
  Future<List<LugarSugerido>> sugerencias(String texto, {int limite = 6}) async {
    buscados.add(texto);
    return lugares;
  }

  @override
  Future<LatLng?> posicion(LugarSugerido lugar) async => lugar.posicion ?? situacion;
}

const _paterna = LugarSugerido(
  id: '1000003934',
  tipo: 'poblacion',
  texto: 'Paterna, Paterna',
  municipio: 'Paterna',
  provincia: 'València/Valencia',
);

void main() {
  Future<MapController> pump(
    WidgetTester tester, {
    List<List<LatLng>> anillos = const [],
    bool buscador = false,
    UbicacionDelDispositivo? ubicacion,
    BuscadorDeLugares? lugares,
    ({String url, LatLngBounds bounds})? imagen,
  }) async {
    final controlador = MapController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ubicacionDelDispositivoProvider.overrideWithValue(
            ubicacion ?? _UbicacionFalsa(error: const UbicacionNoDisponible('sin GPS')),
          ),
          buscadorDeLugaresProvider.overrideWithValue(lugares ?? _BuscadorFalso(const [])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 400,
              child: ParcelMap(
                anillos: anillos,
                imagen: imagen,
                centro: const LatLng(39.5, -0.5),
                controller: controlador,
                buscador: buscador,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controlador;
  }

  testWidgets('los botones acercan y alejan un nivel cada vez', (tester) async {
    final controlador = await pump(tester);
    final inicial = controlador.camera.zoom;

    await tester.tap(find.byTooltip('Acercar'));
    await tester.pump();
    expect(controlador.camera.zoom, inicial + 1);

    await tester.tap(find.byTooltip('Alejar'));
    await tester.tap(find.byTooltip('Alejar'));
    await tester.pump();
    expect(controlador.camera.zoom, inicial - 1);
  });

  testWidgets('no se pasa del último nivel con imagen del IGN', (tester) async {
    final controlador = await pump(tester);

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byTooltip('Acercar'));
    }
    await tester.pump();

    expect(controlador.camera.zoom, MapaBase.zoomMaximo);
  });

  testWidgets('la rueda, pellizcar y arrastrar funcionan además de los botones', (tester) async {
    // El usuario quiso la rueda de vuelta: los botones son para afinar.
    await pump(tester);

    final mapa = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final flags = mapa.options.interactionOptions.flags;

    expect(flags & InteractiveFlag.scrollWheelZoom, isNot(0));
    expect(flags & InteractiveFlag.pinchZoom, isNot(0));
    expect(flags & InteractiveFlag.drag, isNot(0));
  });

  test('el mapa base por defecto es la ortofoto del IGN, con su atribución obligatoria', () {
    expect(MapaBase.urlTeselas, contains('ign.es/wmts/pnoa-ma'));
    expect(MapaBase.urlTeselas, contains('TileMatrixSet=GoogleMapsCompatible'));
    // Condición de uso del IGN: sin esta frase no se puede usar el servicio.
    expect(MapaBase.atribucion, 'PNOA cedido por © Instituto Geográfico Nacional de España');
  });

  testWidgets('los nombres y carreteras salen encima de la foto, y se pueden apagar',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('capa-nombres')), findsOneWidget);
    expect(MapaBase.urlNombres, contains('Layer=IGNBaseOrto'));

    await tester.tap(find.byTooltip('Ocultar nombres y carreteras'));
    await tester.pump();
    expect(find.byKey(const ValueKey('capa-nombres')), findsNothing);

    await tester.tap(find.byTooltip('Mostrar nombres y carreteras'));
    await tester.pump();
    expect(find.byKey(const ValueKey('capa-nombres')), findsOneWidget);
  });

  testWidgets('con parcela dibujada, se encuadra entera y se puede volver a ella', (tester) async {
    const anillo = [
      LatLng(39.600, -0.600),
      LatLng(39.600, -0.598),
      LatLng(39.598, -0.598),
      LatLng(39.598, -0.600),
    ];
    final controlador = await pump(tester, anillos: [anillo]);
    const centroParcela = LatLng(39.599, -0.599);

    // Encuadrada en la parcela, no en `centro`.
    expect(controlador.camera.center.latitude, closeTo(centroParcela.latitude, 1e-3));
    expect(controlador.camera.center.longitude, closeTo(centroParcela.longitude, 1e-3));

    controlador.move(const LatLng(40.4, -3.7), 8);
    await tester.tap(find.byTooltip('Volver a la parcela'));
    await tester.pump();

    expect(controlador.camera.center.latitude, closeTo(centroParcela.latitude, 1e-3));
    expect(controlador.camera.zoom, greaterThan(14));
  });

  testWidgets('la imagen del NDVI se pinta con los píxeles nítidos, sin suavizar', (tester) async {
    // Un píxel de Sentinel-2 son 10 m. Difuminada parecía tener más detalle
    // del que tiene y no se veía qué quedaba fuera de la parcela.
    await pump(
      tester,
      imagen: (
        url: 'https://bucket.example/ndvi.png',
        bounds: LatLngBounds(const LatLng(39.598, -0.600), const LatLng(39.600, -0.598)),
      ),
    );

    final capa = tester.widget<OverlayImageLayer>(find.byType(OverlayImageLayer));
    expect(capa.overlayImages.single.filterQuality, FilterQuality.none);

    // En las pruebas no hay red y la imagen no llega a cargar: se mira cómo
    // se pinta, no qué trae.
    await tester.pump();
    tester.takeException();
  });

  testWidgets('sin parcela no hay botón de volver a ella', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Volver a la parcela'), findsNothing);
  });

  testWidgets('sin buscador (la ficha de una parcela) no hay caja de búsqueda ni ubicación',
      (tester) async {
    await pump(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Mi ubicación'), findsNothing);
  });

  testWidgets('mi ubicación lleva el mapa a donde está el dispositivo', (tester) async {
    final controlador = await pump(
      tester,
      buscador: true,
      ubicacion: _UbicacionFalsa(
        posicion: const PosicionDispositivo(punto: LatLng(39.7, -0.8), precisionMetros: 12),
      ),
    );

    await tester.tap(find.byTooltip('Mi ubicación'));
    await tester.pump();

    expect(controlador.camera.center, const LatLng(39.7, -0.8));
    expect(controlador.camera.zoom, 18);
    expect(find.byKey(const ValueKey('mi-posicion')), findsOneWidget);
    // Precisa: no hay aviso.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('si la ubicación es de kilómetros, lo avisa: no sirve para dibujar', (tester) async {
    await pump(
      tester,
      buscador: true,
      ubicacion: _UbicacionFalsa(
        posicion: const PosicionDispositivo(punto: LatLng(39.7, -0.8), precisionMetros: 2400),
      ),
    );

    await tester.tap(find.byTooltip('Mi ubicación'));
    await tester.pump();

    expect(find.textContaining('Ubicación aproximada (± 2.4 km)'), findsOneWidget);
  });

  testWidgets('si no hay ubicación, dice por qué', (tester) async {
    await pump(
      tester,
      buscador: true,
      ubicacion: _UbicacionFalsa(
          error: const UbicacionNoDisponible('Sin permiso para usar tu ubicación.')),
    );

    await tester.tap(find.byTooltip('Mi ubicación'));
    await tester.pump();

    expect(find.text('Sin permiso para usar tu ubicación.'), findsOneWidget);
  });

  testWidgets('unas coordenadas escritas llevan ahí sin preguntar a nadie', (tester) async {
    final buscador = _BuscadorFalso(const []);
    final controlador = await pump(tester, buscador: true, lugares: buscador);

    await tester.enterText(find.byType(TextField), '39,5116 -0,4536');
    await tester.pump();
    expect(find.text('Ir a 39.51160, -0.45360'), findsOneWidget);

    await tester.tap(find.text('Ir a 39.51160, -0.45360'));
    await tester.pump();

    expect(controlador.camera.center, const LatLng(39.5116, -0.4536));
    expect(find.byKey(const ValueKey('punto-buscado')), findsOneWidget);
    // Las coordenadas no salen del dispositivo.
    expect(buscador.buscados, isEmpty);
  });

  testWidgets('buscar un pueblo y elegirlo lleva el mapa allí', (tester) async {
    final buscador = _BuscadorFalso([_paterna], situacion: const LatLng(39.5116, -0.4536));
    final controlador = await pump(tester, buscador: true, lugares: buscador);

    await tester.enterText(find.byType(TextField), 'paterna');
    // La búsqueda espera a que se deje de escribir.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(buscador.buscados, ['paterna']);
    expect(find.text('Población · València/Valencia'), findsOneWidget);
    expect(find.text(BuscadorDeLugares.atribucion), findsOneWidget);

    await tester.tap(find.text('Paterna, Paterna'));
    await tester.pump();

    expect(controlador.camera.center, const LatLng(39.5116, -0.4536));
    expect(controlador.camera.zoom, 15);
    expect(find.byKey(const ValueKey('punto-buscado')), findsOneWidget);
  });

  testWidgets('Intro elige el primer resultado aunque no haya dado tiempo a verlo', (tester) async {
    final buscador = _BuscadorFalso([_paterna], situacion: const LatLng(39.5116, -0.4536));
    final controlador = await pump(tester, buscador: true, lugares: buscador);

    await tester.enterText(find.byType(TextField), 'paterna');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(controlador.camera.center, const LatLng(39.5116, -0.4536));
  });
}
