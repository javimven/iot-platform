import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:iot_platform_app/core/api/api_client.dart';
import 'package:iot_platform_app/core/api/api_exception.dart';
import 'package:iot_platform_app/core/storage/secure_token_storage.dart';
import 'package:iot_platform_app/features/auth/application/auth_controller.dart';
import 'package:iot_platform_app/features/auth/application/auth_state.dart';
import 'package:iot_platform_app/features/auth/data/auth_api.dart';
import 'package:iot_platform_app/features/campaigns/application/campaigns_controller.dart';
import 'package:iot_platform_app/features/campaigns/data/activity_models.dart';
import 'package:iot_platform_app/features/campaigns/data/campaign_models.dart';
import 'package:iot_platform_app/features/campaigns/data/campaigns_api.dart';
import 'package:iot_platform_app/features/campaigns/presentation/activity_form_screen.dart';
import 'package:iot_platform_app/features/campaigns/presentation/campaign_detail_screen.dart';
import 'package:iot_platform_app/features/campaigns/presentation/campaigns_screen.dart';
import 'package:iot_platform_app/features/installations/application/installations_controller.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';

/// Pantallas de Campañas (BACKLOG.md #60, fase 4). Lo que se fija: el
/// agricultor trabaja con actividades, no se le enseñan ceros que parezcan
/// medidas, y lo que se manda al guardar es lo que espera la API.
class _ApiFalsa extends CampaignsApi {
  _ApiFalsa({this.lista = const [], this.error}) : super(ApiClient());

  final List<CampanaResumida> lista;
  final Object? error;
  Map<String, dynamic>? registrado;

  @override
  Future<List<CampanaResumida>> listar({String? status, String? installationId}) async {
    if (error != null) throw error!;
    return status == 'closed' ? const [] : lista;
  }

  @override
  Future<Actividad> registrar(String campaignId, Map<String, dynamic> cuerpo) async {
    registrado = cuerpo;
    return _actividad();
  }
}

CampanaResumida _campana({
  String id = 'c1',
  String name = 'Aguacate Hass · 2026',
  String status = 'active',
  UltimaActividad? ultima,
}) =>
    CampanaResumida(
      id: id,
      name: name,
      status: status,
      managementMode: 'simple',
      installationId: 'f1',
      installationName: 'Finca Norte',
      startDate: DateTime(2026, 2, 3),
      expectedEndDate: null,
      endDate: null,
      crops: const ['Aguacate Hass'],
      parcelCount: 2,
      areaHa: 8.42,
      lastActivity: ultima,
    );

Campana _ficha({String status = 'active'}) => Campana(
      resumen: _campana(status: status),
      notes: null,
      notebookProfile: const {},
      declaredProductionKg: null,
      closingNotes: null,
      cropUnits: [
        const UnidadDeCultivo(
          id: 'u1',
          cropId: 'aguacate',
          cropName: 'Aguacate',
          variety: 'Hass',
          waterRegime: null,
          growingEnvironment: null,
          productionSystem: null,
          areaHa: null,
          effectiveAreaHa: 8.42,
          expectedYieldKgHa: null,
          parcels: [
            ParcelaDeUnidad(
              parcelId: 'p1',
              name: 'Norte',
              parcelAreaHa: 5,
              areaHa: null,
              effectiveAreaHa: 5,
              deleted: false,
            ),
            ParcelaDeUnidad(
              parcelId: 'p2',
              name: 'Sur',
              parcelAreaHa: 3.42,
              areaHa: null,
              effectiveAreaHa: 3.42,
              deleted: false,
            ),
          ],
        ),
      ],
    );

Actividad _actividad({
  String type = 'irrigation',
  DateTime? fecha,
  Map<String, dynamic>? detalle,
}) =>
    Actividad(
      id: 'a1',
      campaignId: 'c1',
      type: type,
      startDate: fecha ?? DateTime.now(),
      endDate: fecha ?? DateTime.now(),
      startTime: null,
      notes: null,
      origin: 'manual',
      areaHa: 5,
      targets: const [
        DestinoDeActividad(
          parcelId: 'p1',
          parcelName: 'Norte',
          cropUnitId: 'u1',
          cropName: 'Aguacate Hass',
          areaHa: null,
          effectiveAreaHa: 5,
        ),
      ],
      detalle: detalle,
      createdAt: DateTime.now(),
    );

/// El formulario es largo: el botón queda debajo, como en el móvil.
Future<void> guardar(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Guardar'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Guardar'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    Intl.defaultLocale = 'es_ES';
    initializeDateFormatting('es_ES');
  });

  Widget conProveedores(Widget pantalla, List<Override> overrides) => ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _AdminConSesion()),
          installationsListProvider.overrideWith(
            (ref) async => [
              const Installation(
                id: 'f1',
                name: 'Finca Norte',
                locationText: null,
                latitude: null,
                longitude: null,
                status: 'active',
              ),
            ],
          ),
          ...overrides,
        ],
        child: MaterialApp(home: pantalla),
      );

  group('listado', () {
    testWidgets('enseña cada campaña con su finca, superficie y última actividad', (tester) async {
      await tester.pumpWidget(conProveedores(const CampaignsScreen(), [
        campaignsApiProvider.overrideWithValue(
          _ApiFalsa(lista: [
            _campana(ultima: UltimaActividad(type: 'irrigation', date: DateTime.now())),
          ]),
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Aguacate Hass · 2026'), findsOneWidget);
      expect(find.textContaining('Finca Norte'), findsOneWidget);
      expect(find.textContaining('8,42 ha'), findsOneWidget);
      expect(find.text('Riego · hoy'), findsOneWidget);
      expect(find.text('Activa'), findsOneWidget);
    });

    testWidgets('sin campañas, explica qué es una campaña y ofrece crearla', (tester) async {
      await tester.pumpWidget(conProveedores(const CampaignsScreen(), [
        campaignsApiProvider.overrideWithValue(_ApiFalsa()),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Todavía no hay campañas'), findsOneWidget);
      expect(find.text('Nueva campaña'), findsOneWidget);
    });

    testWidgets('sin el módulo contratado, se explica el plan en vez del error', (tester) async {
      await tester.pumpWidget(conProveedores(const CampaignsScreen(), [
        campaignsApiProvider.overrideWithValue(
          _ApiFalsa(
            error: const ApiException(
              status: 403,
              type: 'forbidden',
              title: 'Feature not enabled for this organization: campaigns',
            ),
          ),
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Las campañas no están incluidas en tu plan'), findsOneWidget);
    });
  });

  group('ficha', () {
    testWidgets('la línea de tiempo agrupa por día y resume cada actividad', (tester) async {
      final hoy = DateTime.now();
      await tester.pumpWidget(conProveedores(
        const CampaignDetailScreen(campaignId: 'c1'),
        [
          campanaProvider('c1').overrideWith((ref) async => _ficha()),
          actividadesProvider('c1').overrideWith((ref) async => [
                _actividad(
                  fecha: hoy,
                  detalle: {'amount': 18, 'amountUnit': 'm3_ha', 'volumeM3': 15.3},
                ),
                _actividad(
                  type: 'fertilization',
                  fecha: hoy.subtract(const Duration(days: 1)),
                  detalle: {'productName': 'NPK 15-15-15', 'dose': 320, 'doseUnit': 'kg_ha'},
                ),
              ]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('HOY'), findsOneWidget);
      expect(find.text('AYER'), findsOneWidget);
      expect(find.text('18 m³/ha'), findsOneWidget);
      expect(find.text('NPK 15-15-15 · 320 kg/ha'), findsOneWidget);
      expect(find.text('Registrar actividad'), findsOneWidget);
    });

    testWidgets('sin actividades, invita a apuntar la primera', (tester) async {
      await tester.pumpWidget(conProveedores(
        const CampaignDetailScreen(campaignId: 'c1'),
        [
          campanaProvider('c1').overrideWith((ref) async => _ficha()),
          actividadesProvider('c1').overrideWith((ref) async => <Actividad>[]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Todavía no has apuntado nada'), findsOneWidget);
    });

    testWidgets('una campaña cerrada no ofrece registrar nada', (tester) async {
      await tester.pumpWidget(conProveedores(
        const CampaignDetailScreen(campaignId: 'c1'),
        [
          campanaProvider('c1').overrideWith((ref) async => _ficha(status: 'closed')),
          actividadesProvider('c1').overrideWith((ref) async => <Actividad>[]),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Registrar actividad'), findsNothing);
      expect(find.textContaining('reábrela'), findsOneWidget);
    });
  });

  group('registrar una actividad', () {
    testWidgets('vienen marcadas todas las parcelas y se manda lo rellenado', (tester) async {
      final api = _ApiFalsa();
      await tester.pumpWidget(conProveedores(
        const ActivityFormScreen(campaignId: 'c1', tipo: 'irrigation'),
        [
          campaignsApiProvider.overrideWithValue(api),
          campanaProvider('c1').overrideWith((ref) async => _ficha()),
        ],
      ));
      await tester.pumpAndSettle();

      // Las dos parcelas de la campaña, marcadas.
      expect(tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).length, 2);
      expect(
        tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).every((c) => c.value!),
        isTrue,
      );

      await tester.enterText(find.widgetWithText(TextField, 'Cantidad de agua (opcional)'), '18');
      await guardar(tester);

      expect(api.registrado!['type'], 'irrigation');
      expect(api.registrado!['irrigation'], {'amountUnit': 'm3_ha', 'amount': 18.0});
      expect((api.registrado!['targets'] as List<dynamic>).length, 2);
      expect(api.registrado!['startDate'], isA<String>());
    });

    testWidgets('una coma decimal vale: en España se escribe así', (tester) async {
      final api = _ApiFalsa();
      await tester.pumpWidget(conProveedores(
        const ActivityFormScreen(campaignId: 'c1', tipo: 'harvest'),
        [
          campaignsApiProvider.overrideWithValue(api),
          campanaProvider('c1').overrideWith((ref) async => _ficha()),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Cantidad recolectada'), '1,2');
      await guardar(tester);

      expect((api.registrado!['harvest'] as Map<String, dynamic>)['quantity'], 1.2);
    });

    testWidgets('sin ninguna parcela marcada no se puede guardar', (tester) async {
      await tester.pumpWidget(conProveedores(
        const ActivityFormScreen(campaignId: 'c1', tipo: 'observation'),
        [
          campaignsApiProvider.overrideWithValue(_ApiFalsa()),
          campanaProvider('c1').overrideWith((ref) async => _ficha()),
        ],
      ));
      await tester.pumpAndSettle();

      for (final casilla in find.byType(CheckboxListTile).evaluate().toList()) {
        await tester.tap(find.byWidget(casilla.widget));
        await tester.pump();
      }

      expect(find.text('Marca al menos una parcela.'), findsOneWidget);
      final guardar = tester.widget<FilledButton>(find.byType(FilledButton).last);
      expect(guardar.onPressed, isNull);
    });
  });
}

/// Un administrador de organización con sesión abierta: es quien puede crear
/// campañas y registrar actividades.
class _AdminConSesion extends AuthController {
  _AdminConSesion() : super(AuthApi(ApiClient()), SecureTokenStorage()) {
    state = const AuthState(
      status: AuthStatus.authenticated,
      organizationId: 'org-1',
      roleCode: 'org_admin',
    );
  }
}
