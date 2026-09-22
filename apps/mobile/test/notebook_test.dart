import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:iot_platform_app/core/api/api_client.dart';
import 'package:iot_platform_app/features/campaigns/application/campaigns_controller.dart';
import 'package:iot_platform_app/features/campaigns/data/campaign_models.dart';
import 'package:iot_platform_app/features/campaigns/data/campaigns_api.dart';
import 'package:iot_platform_app/features/campaigns/data/notebook_models.dart';
import 'package:iot_platform_app/features/campaigns/presentation/completeness_view.dart';
import 'package:iot_platform_app/features/campaigns/presentation/notebook_catalog_screen.dart';
import 'package:iot_platform_app/features/campaigns/presentation/notebook_wizard.dart';

/// Cuaderno completo en la app (fase 5 del #60). Lo que se fija: la revisión
/// dice qué falta **con su fuente** y nunca que la campaña cumpla; los
/// catálogos se pueden usar sin teclear dos veces lo mismo; y el cuestionario
/// devuelve respuestas de verdad, no medias tintas.

class _ApiFalsa extends CampaignsApi {
  _ApiFalsa({required this.revisionDevuelta, this.personasGuardadas = const []})
      : super(ApiClient());

  final RevisionDelCuaderno revisionDevuelta;
  final List<PersonaCuaderno> personasGuardadas;
  Map<String, dynamic>? personaCreada;

  @override
  Future<RevisionDelCuaderno> revision(String campaignId) async => revisionDevuelta;

  @override
  Future<List<PersonaCuaderno>> personas({String? installationId}) async => personasGuardadas;

  @override
  Future<List<EquipoCuaderno>> equipos({String? installationId}) async => const [];

  @override
  Future<PersonaCuaderno> crearPersona(Map<String, dynamic> cuerpo) async {
    personaCreada = cuerpo;
    return PersonaCuaderno(
      id: 'nueva',
      kind: cuerpo['kind'] as String,
      displayName: '${cuerpo['firstName']} ${cuerpo['surname1']}'.trim(),
    );
  }
}

RevisionDelCuaderno _revision({
  bool aplica = true,
  int faltan = 2,
  int avisos = 1,
}) =>
    RevisionDelCuaderno.fromJson({
      'campaignId': 'c1',
      'rules': {'id': 'ES-2026.1'},
      'managementMode': aplica ? 'complete' : 'simple',
      'applicable': aplica,
      'missingCount': faltan,
      'warningCount': avisos,
      'campaign': [
        if (faltan > 0)
          {
            'code': 'installation.holder_name',
            'kind': 'missing',
            'label': 'El titular de la finca',
            'why': 'El cuaderno se presenta a nombre del titular.',
            'sourceLabel': 'Cuaderno Único de Explotación (SIEX, Anexo V)',
          },
      ],
      'activities': [
        if (faltan > 1 || avisos > 0)
          {
            'activityId': 'a1',
            'type': 'phytosanitary',
            'startDate': '2026-05-10',
            'items': [
              if (faltan > 1)
                {
                  'code': 'phyto.registry_number:pr1',
                  'kind': 'missing',
                  'label': 'El número de registro de Cobre 50',
                  'why': 'Junto al nombre va su número de autorización.',
                  'sourceLabel': 'Reglamento de Ejecución (UE) 2023/564',
                },
              if (avisos > 0)
                {
                  'code': 'harvest.quantity',
                  'kind': 'warning',
                  'label': 'La cantidad recolectada',
                  'why': 'Sin ella no se puede calcular el rendimiento.',
                  'sourceLabel': 'Necesario para los cálculos de la plataforma',
                },
            ],
          },
      ],
    });

Campana _campanaCompleta() => Campana(
      resumen: CampanaResumida(
        id: 'c1',
        name: 'Olivo · 2026',
        status: 'active',
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
      notebookProfile: const {'version': 1, 'usesPlantProtectionProducts': true},
      declaredProductionKg: null,
      closingNotes: null,
      cropUnits: const [],
    );

Widget _conProveedores(Widget pantalla, CampaignsApi api) => ProviderScope(
      overrides: [
        campaignsApiProvider.overrideWithValue(api),
        // Quien mantiene los catálogos es un técnico o el admin (PERMISSIONS
        // §14 ter); sin esto, el rol sería nulo y no saldrían los botones.
        permisosDeCampanaProvider.overrideWithValue(const PermisosDeCampana('org_admin')),
      ],
      child: MaterialApp(home: pantalla),
    );

void main() {
  setUpAll(() {
    Intl.defaultLocale = 'es_ES';
    initializeDateFormatting('es_ES');
  });

  group('modelos del cuaderno', () {
    test('la revisión trae los contadores, los avisos y la versión de las reglas', () {
      final revision = _revision();

      expect(revision.aplica, isTrue);
      expect(revision.versionDeReglas, 'ES-2026.1');
      expect(revision.faltan, 2);
      expect(revision.avisos, 1);
      expect(revision.deLaCampana.single.label, 'El titular de la finca');
      expect(revision.deActividades.single.avisos.length, 2);
      expect(revision.deActividades.single.date, DateTime(2026, 5, 10));
      expect(revision.sinPendientes, isFalse);
    });

    test('cada aviso sabe si es una falta o un aviso, y de dónde sale', () {
      final avisos = _revision().deActividades.single.avisos;

      expect(avisos.first.esFalta, isTrue);
      expect(avisos.first.sourceLabel, contains('2023/564'));
      expect(avisos.last.esFalta, isFalse);
      expect(avisos.last.sourceLabel, contains('plataforma'));
    });

    test('lo pendiente se cuenta en singular y en plural', () {
      expect(textoDePendientes(_revision(faltan: 1, avisos: 0)), '1 dato pendiente');
      expect(textoDePendientes(_revision(faltan: 2, avisos: 1)), '2 datos pendientes y 1 aviso');
      expect(textoDePendientes(_revision(faltan: 0, avisos: 0)), 'No falta nada por apuntar');
    });

    test('una persona se lee con el nombre montado y una empresa por su razón social', () {
      final persona = PersonaCuaderno.fromJson({
        'id': 'p1',
        'kind': 'own_staff',
        'displayName': 'Ana Ruiz',
        'nif': '12345678Z',
        'ropoNumber': 'AND-1234',
      });
      expect(persona.displayName, 'Ana Ruiz');
      expect(persona.nif, '12345678Z');
      expect(persona.deleted, isFalse);
    });

    test('un equipo lee sus fechas sin desplazarse de día', () {
      final equipo = EquipoCuaderno.fromJson({
        'id': 'e1',
        'description': 'Atomizador',
        'displayName': 'Atomizador · Hardi',
        'lastInspectionOn': '2025-11-03',
      });
      expect(equipo.lastInspectionOn, DateTime(2025, 11, 3));
    });

    test('al guardar solo se manda lo que el formulario ha tocado', () {
      final cuerpo = PersonaCuaderno.cuerpo(kind: 'adviser', firstName: ' Ana ');

      expect(cuerpo['kind'], 'adviser');
      expect(cuerpo['firstName'], 'Ana');
      // La finca no se manda si no se ha tocado: mandar null la vaciaría.
      expect(cuerpo.containsKey('installationId'), isFalse);
      expect(cuerpo.containsKey('nif'), isFalse);
    });

    test('el perfil solo viaja en una campaña completa', () {
      final sencilla = NuevaCampana(
        managementMode: 'simple',
        startDate: DateTime(2026, 3, 1),
        parcelIds: const ['p1'],
        notebookProfile: const {'appliesFertilizers': true},
      ).toJson();
      expect(sencilla.containsKey('notebookProfile'), isFalse);

      final completa = NuevaCampana(
        managementMode: 'complete',
        startDate: DateTime(2026, 3, 1),
        parcelIds: const ['p1'],
        notebookProfile: const {'appliesFertilizers': true},
      ).toJson();
      expect(completa['notebookProfile'], {'appliesFertilizers': true});
    });
  });

  group('revisión en pantalla', () {
    testWidgets('enseña lo que falta con su fuente, y nunca dice que cumple', (tester) async {
      await tester.pumpWidget(
        _conProveedores(
          CompletenessView(campana: _campanaCompleta()),
          _ApiFalsa(revisionDevuelta: _revision()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 datos pendientes y 1 aviso'), findsOneWidget);
      expect(find.text('El titular de la finca'), findsOneWidget);
      expect(find.text('El número de registro de Cobre 50'), findsOneWidget);
      expect(find.textContaining('Reglamento de Ejecución (UE) 2023/564'), findsOneWidget);
      expect(find.textContaining('cumple'), findsNothing);
    });

    testWidgets('sin nada pendiente, lo dice sin prometer que sea válido', (tester) async {
      await tester.pumpWidget(
        _conProveedores(
          CompletenessView(campana: _campanaCompleta()),
          _ApiFalsa(revisionDevuelta: _revision(faltan: 0, avisos: 0)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No falta nada por apuntar'), findsOneWidget);
      expect(find.textContaining('no que el cuaderno sea válido'), findsOneWidget);
    });

    testWidgets('a una campaña sencilla no se le reprocha nada', (tester) async {
      await tester.pumpWidget(
        _conProveedores(
          CompletenessView(campana: _campanaCompleta()),
          _ApiFalsa(revisionDevuelta: _revision(aplica: false, faltan: 0, avisos: 0)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Esta campaña es sencilla'), findsOneWidget);
    });
  });

  group('cuestionario del cuaderno', () {
    testWidgets('devuelve una respuesta por pregunta, y lo marcado va a verdadero', (tester) async {
      Map<String, bool>? respuestas;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                respuestas = await preguntarCuestionarioDelCuaderno(context);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Marca lo que hagas en esta campaña'), findsOneWidget);
      await tester.tap(find.text(preguntasDelCuaderno.first.pregunta));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Guardar'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(respuestas, isNotNull);
      expect(respuestas!.length, preguntasDelCuaderno.length);
      expect(respuestas![preguntasDelCuaderno.first.clave], isTrue);
      expect(respuestas![preguntasDelCuaderno.last.clave], isFalse);
    });
  });

  group('catálogo de personas', () {
    testWidgets('sin personas, explica para qué sirve y ofrece añadir', (tester) async {
      await tester.pumpWidget(
        _conProveedores(const NotebookCatalogScreen(), _ApiFalsa(revisionDevuelta: _revision())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Todavía no hay personas'), findsOneWidget);
      expect(find.text('Añadir persona'), findsOneWidget);
    });

    testWidgets('con personas, se lee el nombre, el tipo y su ROPO', (tester) async {
      await tester.pumpWidget(
        _conProveedores(
          const NotebookCatalogScreen(),
          _ApiFalsa(
            revisionDevuelta: _revision(),
            personasGuardadas: const [
              PersonaCuaderno(
                id: 'p1',
                kind: 'own_staff',
                displayName: 'Ana Ruiz',
                nif: '12345678Z',
                ropoNumber: 'AND-1234',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ana Ruiz'), findsOneWidget);
      expect(find.textContaining('Personal propio'), findsOneWidget);
      expect(find.textContaining('ROPO AND-1234'), findsOneWidget);
    });
  });
}
