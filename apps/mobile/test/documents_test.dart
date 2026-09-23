import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:iot_platform_app/core/api/api_client.dart';
import 'package:iot_platform_app/features/campaigns/application/campaigns_controller.dart';
import 'package:iot_platform_app/features/campaigns/data/campaign_models.dart';
import 'package:iot_platform_app/features/campaigns/data/campaigns_api.dart';
import 'package:iot_platform_app/features/campaigns/data/document_models.dart';
import 'package:iot_platform_app/features/campaigns/presentation/adjuntos.dart';
import 'package:iot_platform_app/features/campaigns/presentation/documents_screen.dart';

/// Fotos y documentos del cuaderno en la app (BACKLOG.md #60, fase 6). Lo que
/// se fija: lo adjuntado se ve donde se adjuntó, un enlace caducado no rompe
/// la pantalla, y quitar algo avisa de que puede seguir en otro sitio.

class _ApiFalsa extends CampaignsApi {
  _ApiFalsa({this.lista = const []}) : super(ApiClient());

  List<DocumentoDelCuaderno> lista;
  ({String campaignId, String? activityId, String documentId})? quitado;

  @override
  Future<List<DocumentoDelCuaderno>> documentos(String campaignId) async => lista;

  @override
  Future<void> quitarDocumento(String campaignId, String documentId, {String? activityId}) async {
    quitado = (campaignId: campaignId, activityId: activityId, documentId: documentId);
  }
}

DocumentoDelCuaderno _documento({
  String id = 'd1',
  String? activityId,
  String mediaType = 'image/jpeg',
  String tipo = 'photo',
  String? title,
}) =>
    DocumentoDelCuaderno.fromJson({
      'id': id,
      'documentType': tipo,
      'title': title,
      'filename': 'albaran.jpg',
      'mediaType': mediaType,
      'byteSize': 2 * 1024 * 1024,
      'campaignId': 'c1',
      'activityId': activityId,
      'createdAt': '2026-09-20T10:00:00.000Z',
      'url': 'https://ejemplo.invalid/foto.jpg',
      'urlExpiresAt': '2026-09-20T10:15:00.000Z',
    });

Campana _campana() => Campana(
      resumen: CampanaResumida(
        id: 'c1',
        name: 'Almendro · 2026',
        status: 'active',
        managementMode: 'simple',
        installationId: 'f1',
        installationName: 'Finca de los Papeles',
        startDate: DateTime(2026, 3, 1),
        expectedEndDate: null,
        endDate: null,
        crops: const ['Almendro'],
        parcelCount: 1,
        areaHa: 4,
        lastActivity: null,
      ),
      notes: null,
      notebookProfile: const {},
      declaredProductionKg: null,
      closingNotes: null,
      cropUnits: const [],
    );

Widget _con(Widget pantalla, CampaignsApi api) => ProviderScope(
      overrides: [
        campaignsApiProvider.overrideWithValue(api),
        permisosDeCampanaProvider.overrideWithValue(const PermisosDeCampana('org_admin')),
      ],
      child: MaterialApp(home: pantalla),
    );

void main() {
  setUpAll(() {
    Intl.defaultLocale = 'es_ES';
    initializeDateFormatting('es_ES');
  });

  group('modelo del documento', () {
    test('lee lo que devuelve la API, con las fechas en local', () {
      final documento = _documento(activityId: 'a1', title: 'Albarán');

      expect(documento.esImagen, isTrue);
      expect(documento.nombre, 'Albarán');
      expect(documento.activityId, 'a1');
      expect(documento.urlExpiresAt.isAfter(documento.createdAt), isTrue);
    });

    test('sin título, el nombre es el del fichero', () {
      expect(_documento().nombre, 'albaran.jpg');
    });

    test('el tamaño se lee como lo diría una persona', () {
      expect(tamanoLegible(800), '800 B');
      expect(tamanoLegible(2048), '2 kB');
      expect(tamanoLegible(2 * 1024 * 1024), '2,0 MB');
      expect(tamanoLegible(15 * 1024 * 1024), '15 MB');
    });

    test('cada tipo tiene su nombre en español, y lo desconocido no revienta', () {
      expect(etiquetaDeDocumento('delivery_note'), 'Albarán');
      expect(etiquetaDeDocumento('fertilization_plan'), 'Plan de abonado');
      expect(etiquetaDeDocumento('lo_que_venga'), 'Documento');
    });
  });

  group('adjuntos de una actividad', () {
    testWidgets('enseña los de esa actividad y no los de otras', (tester) async {
      final api = _ApiFalsa(lista: [
        _documento(id: 'd1', activityId: 'a1', title: 'De la actividad'),
        _documento(id: 'd2', activityId: 'a2', title: 'De otra'),
        _documento(id: 'd3', title: 'De la campaña'),
      ]);
      await tester.pumpWidget(_con(
        const Scaffold(body: Adjuntos(campaignId: 'c1', activityId: 'a1')),
        api,
      ));
      await tester.pumpAndSettle();

      // Las miniaturas no llevan texto: se cuentan por lo que se pide al
      // servidor y por el botón de añadir, que siempre está.
      expect(find.text('Fotos y documentos'), findsOneWidget);
      expect(find.text('Añadir'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('sin poder tocar (campaña cerrada), no ofrece añadir', (tester) async {
      await tester.pumpWidget(_con(
        const Scaffold(
          body: Adjuntos(campaignId: 'c1', activityId: 'a1', sePuedeTocar: false),
        ),
        _ApiFalsa(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Añadir'), findsNothing);
      expect(find.text('Sin adjuntos'), findsOneWidget);
    });

    testWidgets('quitar avisa de que puede seguir en otro sitio, y llama a la API', (tester) async {
      final api = _ApiFalsa(lista: [_documento(id: 'd1', activityId: 'a1')]);
      await tester.pumpWidget(_con(
        const Scaffold(body: Adjuntos(campaignId: 'c1', activityId: 'a1')),
        api,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.textContaining('allí se queda'), findsOneWidget);

      await tester.tap(find.text('Quitar'));
      await tester.pumpAndSettle();
      expect(api.quitado?.documentId, 'd1');
      expect(api.quitado?.activityId, 'a1');
    });
  });

  group('pantalla de documentos', () {
    testWidgets('separa los de la campaña de los de las actividades', (tester) async {
      final api = _ApiFalsa(lista: [
        _documento(id: 'd1', title: 'Analítica del agua', tipo: 'analysis'),
        _documento(id: 'd2', activityId: 'a1', title: 'Albarán de la cosecha'),
      ]);
      await tester.pumpWidget(_con(DocumentsScreen(campana: _campana()), api));
      await tester.pumpAndSettle();

      expect(find.text('De la campaña'), findsOneWidget);
      expect(find.text('De las actividades'), findsOneWidget);
      // El de la actividad se lista con su tipo y su tamaño; el de la campaña
      // va en la tira de miniaturas de arriba.
      expect(find.text('Albarán de la cosecha'), findsOneWidget);
      expect(find.textContaining('2,0 MB'), findsOneWidget);
    });

    testWidgets('sin adjuntos en actividades, dice dónde se añaden', (tester) async {
      await tester.pumpWidget(_con(DocumentsScreen(campana: _campana()), _ApiFalsa()));
      await tester.pumpAndSettle();

      expect(find.textContaining('desde la propia'), findsOneWidget);
    });
  });
}
