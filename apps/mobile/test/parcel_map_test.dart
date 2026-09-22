import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/satellite/presentation/parcel_map.dart';
import 'package:latlong2/latlong.dart';

/// Mapa de una parcela (BACKLOG.md #36). Lo que se fija aquí son las dos
/// decisiones que pidió el usuario al verlo por primera vez: ortofoto en vez
/// de callejero, y zoom con botones en vez de con la rueda.
void main() {
  Future<MapController> pump(WidgetTester tester) async {
    final controlador = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: ParcelMap(
              anillos: const [],
              centro: const LatLng(39.5, -0.5),
              controller: controlador,
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

  testWidgets('la rueda del ratón no hace zoom: el mapa vive dentro de una página con scroll',
      (tester) async {
    await pump(tester);

    final mapa = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final flags = mapa.options.interactionOptions.flags;

    expect(flags & InteractiveFlag.scrollWheelZoom, 0);
    // Pellizcar y arrastrar siguen funcionando en pantallas táctiles.
    expect(flags & InteractiveFlag.pinchZoom, isNot(0));
    expect(flags & InteractiveFlag.drag, isNot(0));
  });

  test('el mapa base por defecto es la ortofoto del IGN, con su atribución obligatoria', () {
    expect(MapaBase.urlTeselas, contains('ign.es/wmts/pnoa-ma'));
    expect(MapaBase.urlTeselas, contains('TileMatrixSet=GoogleMapsCompatible'));
    // Condición de uso del IGN: sin esta frase no se puede usar el servicio.
    expect(MapaBase.atribucion, 'PNOA cedido por © Instituto Geográfico Nacional de España');
  });
}
