import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/campaigns/data/activity_models.dart';
import 'package:iot_platform_app/features/campaigns/data/campaign_models.dart';

/// Lo que llega de la API y lo que se manda (BACKLOG.md #60, fase 4). Lo que
/// se fija aquí: las fechas del cuaderno son fechas, no instantes, y el
/// resumen distingue "no hay dato" de "cero".
void main() {
  group('fechas sin hora', () {
    test('una fecha del campo no se desplaza un día', () {
      final fecha = leerFecha('2026-02-03');

      expect(fecha.year, 2026);
      expect(fecha.month, 2);
      expect(fecha.day, 3);
      expect(escribirFecha(fecha), '2026-02-03');
    });

    test('se escribe con ceros delante, como espera la API', () {
      expect(escribirFecha(DateTime(2026, 9, 5)), '2026-09-05');
    });
  });

  test('una campaña trae su finca, sus cultivos y su última actividad', () {
    final campana = Campana.fromJson({
      'id': 'c1',
      'name': 'Aguacate Hass · 2026',
      'status': 'active',
      'managementMode': 'simple',
      'installation': {'id': 'f1', 'name': 'Finca Norte'},
      'startDate': '2026-02-03',
      'expectedEndDate': null,
      'endDate': null,
      'crops': ['Aguacate Hass'],
      'parcelCount': 2,
      'areaHa': 8.42,
      'lastActivity': {'type': 'irrigation', 'date': '2026-09-18'},
      'notes': null,
      'notebookProfile': <String, dynamic>{},
      'cropUnits': [
        {
          'id': 'u1',
          'cropId': 'aguacate',
          'cropName': 'Aguacate',
          'variety': 'Hass',
          'areaHa': null,
          'parcelsAreaHa': 8.42,
          'effectiveAreaHa': 8.42,
          'expectedYieldKgHa': 12000,
          'parcels': [
            {
              'parcelId': 'p1',
              'name': 'Norte',
              'parcelAreaHa': 5.0,
              'areaHa': null,
              'effectiveAreaHa': 5.0,
              'deleted': false,
            },
            {
              'parcelId': 'p2',
              'name': 'Vieja',
              'parcelAreaHa': 3.42,
              'areaHa': null,
              'effectiveAreaHa': 3.42,
              'deleted': true,
            },
          ],
        },
      ],
    });

    expect(campana.resumen.installationName, 'Finca Norte');
    expect(campana.resumen.estaCerrada, isFalse);
    expect(campana.cropUnits.single.nombre, 'Aguacate Hass');
    expect(campana.resumen.lastActivity!.date, DateTime(2026, 9, 18));
    // Una parcela borrada no se ofrece para registrar nada nuevo.
    expect(campana.parcelas.map((p) => p.parcela.name), ['Norte']);
  });

  test('el alta solo manda lo que se ha rellenado', () {
    final cuerpo = NuevaCampana(
      managementMode: 'complete',
      startDate: DateTime(2026, 2, 3),
      parcelIds: const ['p1', 'p2'],
      cropId: 'aguacate',
      variety: ' Hass ',
      name: '   ',
    ).toJson();

    expect(cuerpo['managementMode'], 'complete');
    expect(cuerpo['startDate'], '2026-02-03');
    expect(cuerpo.containsKey('name'), isFalse); // solo espacios: que lo ponga el backend
    expect(cuerpo.containsKey('expectedEndDate'), isFalse);
    final unidad = (cuerpo['cropUnits'] as List<dynamic>).single as Map<String, dynamic>;
    expect(unidad['cropId'], 'aguacate');
    expect(unidad['variety'], 'Hass');
    expect(unidad['parcels'], [
      {'parcelId': 'p1'},
      {'parcelId': 'p2'},
    ]);
  });

  test('una actividad trae el detalle de su tipo y sus parcelas', () {
    final actividad = Actividad.fromJson({
      'id': 'a1',
      'campaignId': 'c1',
      'type': 'irrigation',
      'startDate': '2026-09-18',
      'endDate': '2026-09-18',
      'startTime': null,
      'notes': null,
      'origin': 'manual',
      'areaHa': 0.85,
      'targets': [
        {
          'parcelId': 'p1',
          'parcelName': 'Norte',
          'cropUnitId': 'u1',
          'cropName': 'Aguacate Hass',
          'areaHa': null,
          'effectiveAreaHa': 0.85,
        },
      ],
      'irrigation': {'amount': 18, 'amountUnit': 'm3_ha', 'volumeM3': 15.3},
      'fertilization': null,
      'createdAt': '2026-09-18T10:00:00.000Z',
    });

    expect(actividad.esDeVariosDias, isFalse);
    expect(actividad.detalle!['volumeM3'], 15.3);
    expect(actividad.targets.single.parcelName, 'Norte');
  });

  test('el resumen distingue un apartado sin datos de uno con ceros', () {
    final resumen = ResumenCampana.fromJson({
      'campaignId': 'c1',
      'areaHa': 4,
      'activityCount': 2,
      'lastActivity': {'type': 'harvest', 'date': '2026-09-20'},
      'irrigation': {'count': 2, 'volumeM3': 72, 'volumeM3PerHa': 18, 'withoutVolume': 1},
      'fertilization': null,
      'phytosanitary': null,
      'harvest': null,
      'fieldWork': {'count': 3},
      'observations': null,
      'cropUnits': [
        {'id': 'u1', 'cropName': 'Aguacate', 'areaHa': 4, 'harvestKg': null, 'yieldKgHa': null},
      ],
    });

    expect(resumen.riego!.volumeM3, 72);
    expect(resumen.riego!.withoutVolume, 1);
    expect(resumen.abonado, isNull);
    expect(resumen.cosecha, isNull);
    expect(resumen.labores, 3);
    expect(resumen.vacio, isFalse);
  });
}
