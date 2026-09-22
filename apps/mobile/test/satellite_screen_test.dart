import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/installations/application/installations_controller.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';
import 'package:iot_platform_app/features/parcels/application/parcels_controller.dart';
import 'package:iot_platform_app/features/parcels/data/parcel_models.dart';
import 'package:iot_platform_app/features/satellite/application/satellite_controller.dart';
import 'package:iot_platform_app/features/satellite/data/satellite_models.dart';
import 'package:iot_platform_app/features/satellite/presentation/ndvi_chart.dart';
import 'package:iot_platform_app/features/satellite/presentation/satellite_screen.dart';

/// Pantalla de Satélite (BACKLOG.md #36). Lo que se comprueba aquí son los
/// estados: una finca sin parcelas, una parcela sin observaciones y una con
/// datos. No se prueba el mapa tesela a tesela — eso pide red y no dice nada.
void main() {
  const finca = Installation(
    id: 'finca-1',
    name: 'Finca del Río',
    locationText: null,
    latitude: 39.5,
    longitude: -0.5,
    status: 'active',
  );

  final parcela = Parcel.fromJson(const {
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
    'areaM2': 95490.0,
    'bbox': [-0.5, 39.5, -0.499, 39.501],
    'geometryVersion': 1,
  });

  final observacion = ObservacionSatelite.fromJson(const {
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
      'validPixelFraction': 0.92,
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
    'assets': [],
  });

  final serie = [
    PuntoSatelite.fromJson(const {
      'tsOrigin': '2026-09-10T10:42:19.000Z',
      'value': 0.58,
      'median': 0.6,
      'observationId': 'obs-0',
      'qualityStatus': 'good',
    }),
    PuntoSatelite.fromJson(const {
      'tsOrigin': '2026-09-15T10:42:19.000Z',
      'value': 0.63,
      'median': 0.66,
      'observationId': 'obs-1',
      'qualityStatus': 'partial',
    }),
  ];

  Future<void> pump(
    WidgetTester tester, {
    List<Installation> fincas = const [],
    List<Parcel> parcelas = const [],
    ObservacionSatelite? ultima,
    List<PuntoSatelite> puntos = const [],
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          installationsListProvider.overrideWith((ref) async => fincas),
          parcelasDeFincaProvider('finca-1').overrideWith((ref) async => parcelas),
          ultimaObservacionProvider('parcela-1').overrideWith((ref) async => ultima),
          serieNdviProvider('parcela-1').overrideWith((ref) async => puntos),
        ],
        child: const MaterialApp(home: SatelliteScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin fincas invita a crear una antes de nada', (tester) async {
    await pump(tester);

    expect(find.text('Todavía no hay fincas'), findsOneWidget);
  });

  testWidgets('una finca sin parcelas ofrece dibujar la primera', (tester) async {
    await pump(tester, fincas: [finca]);

    expect(find.text('Esta finca no tiene parcelas'), findsOneWidget);
    expect(find.text('Crear parcela'), findsOneWidget);
  });

  testWidgets('una parcela sin observaciones lo explica en vez de enseñar un 0,00', (tester) async {
    await pump(tester, fincas: [finca], parcelas: [parcela]);

    expect(find.text('Sin observaciones todavía'), findsOneWidget);
    expect(find.text('Buscar ahora'), findsOneWidget);
    // Lo importante: no se inventa un NDVI donde no hay dato.
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('con observación enseña fecha, calidad y las dos cifras de NDVI', (tester) async {
    await pump(
      tester,
      fincas: [finca],
      parcelas: [parcela],
      ultima: observacion,
      puntos: serie,
    );

    expect(find.text('Observación del 15/09/2026'), findsOneWidget);
    expect(find.text('92 % válido'), findsOneWidget);
    expect(find.text('NDVI medio'), findsOneWidget);
    expect(find.text('0.63'), findsOneWidget);
    // La mediana aguanta mejor los píxeles raros del borde, por eso va también.
    expect(find.text('NDVI mediano'), findsOneWidget);
    expect(find.text('0.66'), findsOneWidget);
  });

  testWidgets('avisa de la resolución: 10 m por píxel, ni un centímetro menos', (tester) async {
    await pump(tester, fincas: [finca], parcelas: [parcela], ultima: observacion);

    expect(find.textContaining('10 m por píxel'), findsOneWidget);
  });

  testWidgets('dibuja la evolución cuando hay puntos', (tester) async {
    await pump(
      tester,
      fincas: [finca],
      parcelas: [parcela],
      ultima: observacion,
      puntos: serie,
    );

    expect(find.text('Evolución del NDVI'), findsOneWidget);
    expect(find.byType(NdviChart), findsOneWidget);
  });

  testWidgets('sin puntos todavía, lo dice en vez de pintar una gráfica vacía', (tester) async {
    await pump(tester, fincas: [finca], parcelas: [parcela], ultima: observacion);

    expect(find.byType(NdviChart), findsNothing);
    expect(
      find.textContaining('no hay suficientes observaciones'),
      findsOneWidget,
    );
  });

  testWidgets('con una parcela pequeña avisa de que la media se mezcla con el borde',
      (tester) async {
    final pequena = Parcel.fromJson({
      ...(parcela.toJsonParaPrueba()),
      'areaM2': 1200.0, // ~12 píxeles de Sentinel-2
    });

    await pump(tester, fincas: [finca], parcelas: [pequena], ultima: observacion);

    expect(find.textContaining('pequeña para una resolución de 10 m'), findsOneWidget);
  });
}

/// Ayuda de prueba: reconstruye el JSON de una parcela para variar un campo.
extension on Parcel {
  Map<String, dynamic> toJsonParaPrueba() => {
        'id': id,
        'installationId': installationId,
        'name': name,
        'notes': notes,
        'geometry': contorno.toGeoJson(),
        'areaM2': areaM2,
        'bbox': bbox,
        'geometryVersion': geometryVersion,
      };
}
