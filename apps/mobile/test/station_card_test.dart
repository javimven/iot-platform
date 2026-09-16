import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/directory/data/directory_models.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';
import 'package:iot_platform_app/features/readings/application/reading_history_controller.dart';
import 'package:iot_platform_app/features/stations/application/stations_controller.dart';
import 'package:iot_platform_app/features/stations/presentation/combined_station_chart.dart';
import 'package:iot_platform_app/features/stations/presentation/station_card.dart';

/// Tarjeta de Estación (BACKLOG.md #48): abre con las píldoras de cada sensor
/// y ninguna gráfica; al activar una magnitud aparece la gráfica de ese
/// sensor con su selector de rango encima.
void main() {
  const gateway = Gateway(
    id: 'gw-1',
    installationId: 'inst-1',
    name: 'Estación WSC2-N',
    connectivityType: 'direct_nbiot',
    status: 'online',
    lastSeenAt: null,
  );

  LatestReading reading(String channelId, String code, String sensorId, String externalId, String label) =>
      LatestReading(
        channelId: channelId,
        channelTypeCode: code,
        value: 25,
        tsOrigin: DateTime.utc(2026, 9, 16, 13),
        tsReceived: DateTime.utc(2026, 9, 16, 13),
        sensorId: sensorId,
        sensorExternalIdentifier: externalId,
        sensorLabel: label,
      );

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gatewayLatestReadingsProvider('gw-1').overrideWith(
            (ref) async => [
              reading('ch-temp-soil', 'temperature_soil', 's2', 'A2', 'Sonda de suelo redonda'),
              reading('ch-hum-air', 'humidity_air', 's4', 'A4', 'Ambiente'),
              reading('ch-temp-air', 'temperature_air', 's4', 'A4', 'Ambiente'),
            ],
          ),
          stationChannelHistoryProvider.overrideWith((ref, key) async => const []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: StationCard(gateway: gateway))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('abre con los sensores y sus píldoras, sin gráficas ni selector de rango', (tester) async {
    await pumpCard(tester);

    expect(find.text('Sonda de suelo redonda · A2'), findsOneWidget);
    expect(find.text('Ambiente · A4'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(3));
    expect(find.byType(SegmentedButton<HistoryRange>), findsNothing);
  });

  testWidgets('al activar una magnitud aparece el selector de rango solo en ese sensor', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.textContaining('Temperatura ambiente:'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<HistoryRange>), findsOneWidget);

    // Selector encima de la gráfica del sensor Ambiente, debajo de sus píldoras.
    final selectorTop = tester.getTopLeft(find.byType(SegmentedButton<HistoryRange>)).dy;
    final ambientTitle = tester.getTopLeft(find.text('Ambiente · A4')).dy;
    final ambientPill = tester.getTopLeft(find.textContaining('Temperatura ambiente:')).dy;
    expect(selectorTop, greaterThan(ambientTitle));
    expect(selectorTop, greaterThan(ambientPill));
    expect(tester.getTopLeft(find.byType(CombinedStationChart)).dy, greaterThan(selectorTop));

    // Quitar la magnitud cierra la gráfica y su selector.
    await tester.tap(find.textContaining('Temperatura ambiente:'));
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton<HistoryRange>), findsNothing);
  });
}
