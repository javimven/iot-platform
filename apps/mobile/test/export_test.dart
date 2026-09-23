import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/core/api/api_client.dart';
import 'package:iot_platform_app/features/campaigns/application/campaigns_controller.dart';
import 'package:iot_platform_app/features/campaigns/data/campaign_models.dart';
import 'package:iot_platform_app/features/campaigns/data/campaigns_api.dart';
import 'package:iot_platform_app/features/campaigns/presentation/exportar_cuaderno.dart';

/// Exportar el cuaderno desde la app (BACKLOG.md #60, fase 7). Lo que se fija:
/// que cada opción pida lo que dice, y que el nombre del fichero que manda el
/// servidor se lea con los acentos bien.

class _ApiFalsa extends CampaignsApi {
  _ApiFalsa() : super(ApiClient());

  final peticiones = <({String formato, String? layout})>[];

  @override
  Future<({List<int> bytes, String? nombre, String mediaType})> exportar(
    String campaignId, {
    required String formato,
    String? layout,
  }) async {
    peticiones.add((formato: formato, layout: layout));
    return (bytes: const [1, 2, 3], nombre: 'Cuaderno - Olivo.pdf', mediaType: 'application/pdf');
  }
}

Campana _campana({String status = 'active'}) => Campana(
      resumen: CampanaResumida(
        id: 'c1',
        name: 'Olivo · 2026',
        status: status,
        managementMode: 'complete',
        installationId: 'f1',
        installationName: 'Finca del Olivar',
        startDate: DateTime(2026, 3, 1),
        expectedEndDate: null,
        endDate: null,
        crops: const ['Olivo'],
        parcelCount: 1,
        areaHa: 3.5,
        lastActivity: null,
      ),
      notes: null,
      notebookProfile: const {},
      declaredProductionKg: null,
      closingNotes: null,
      cropUnits: const [],
    );

Widget _con(CampaignsApi api, Campana campana) => ProviderScope(
      overrides: [campaignsApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => exportarCuaderno(context, ref, campana),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

void main() {
  group('nombre de la descarga', () {
    test('se prefiere el nombre en UTF-8, que es el que trae los acentos', () {
      const cabecera = 'attachment; filename="Cuaderno - Olivo  2026.pdf"; '
          "filename*=UTF-8''Cuaderno%20-%20Olivo%20%C2%B7%202026.pdf";
      expect(nombreDeLaCabecera(cabecera), 'Cuaderno - Olivo · 2026.pdf');
    });

    test('sin el de UTF-8 vale el sencillo, y sin cabecera no hay nombre', () {
      expect(nombreDeLaCabecera('attachment; filename="Cuaderno.csv"'), 'Cuaderno.csv');
      expect(nombreDeLaCabecera(null), isNull);
      expect(nombreDeLaCabecera('attachment'), isNull);
    });
  });

  group('hoja de exportar', () {
    testWidgets('ofrece las dos disposiciones del PDF, el CSV y el JSON', (tester) async {
      await tester.pumpWidget(_con(_ApiFalsa(), _campana()));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Informe en PDF'), findsOneWidget);
      expect(find.text('PDF con los apartados del cuaderno de explotación'), findsOneWidget);
      expect(find.text('Hoja de cálculo (CSV)'), findsOneWidget);
      expect(find.text('Datos completos (JSON)'), findsOneWidget);
    });

    testWidgets('cada opción pide su formato y su disposición', (tester) async {
      final api = _ApiFalsa();
      await tester.pumpWidget(_con(api, _campana()));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PDF con los apartados del cuaderno de explotación'));
      await tester.pumpAndSettle();

      expect(api.peticiones.single.formato, 'pdf');
      expect(api.peticiones.single.layout, 'cue');
    });

    testWidgets('fuera del navegador se dice que la descarga es del ordenador', (tester) async {
      final api = _ApiFalsa();
      await tester.pumpWidget(_con(api, _campana()));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hoja de cálculo (CSV)'));
      await tester.pumpAndSettle();

      // En las pruebas no hay navegador: el fichero se genera, pero no hay
      // dónde dejarlo, y eso se dice en vez de fingir que se ha guardado.
      expect(api.peticiones.single.formato, 'csv');
      expect(find.textContaining('desde el ordenador'), findsWidgets);
    });

    testWidgets('una campaña cerrada avisa de que se exporta como quedó', (tester) async {
      await tester.pumpWidget(_con(_ApiFalsa(), _campana(status: 'closed')));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.textContaining('tal como quedó al cerrarla'), findsOneWidget);
    });
  });
}
