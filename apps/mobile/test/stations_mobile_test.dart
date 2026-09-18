import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iot_platform_app/features/directory/data/directory_models.dart';
import 'package:iot_platform_app/features/installations/data/installation_models.dart';
import 'package:iot_platform_app/features/readings/data/reading_history_models.dart';
import 'package:iot_platform_app/features/stations/application/station_detail_controller.dart';
import 'package:iot_platform_app/features/stations/application/stations_controller.dart';
import 'package:iot_platform_app/features/stations/presentation/station_detail_screen.dart';
import 'package:iot_platform_app/features/stations/presentation/stations_screen.dart';

/// Estaciones en el móvil (BACKLOG.md #49): resumen al entrar (B), pantalla de
/// la estación con la principal dibujada (C) y una gráfica por magnitud (D).
Gateway _gateway(String id, String name) => Gateway(
      id: id,
      installationId: 'inst-1',
      name: name,
      connectivityType: 'direct_nbiot',
      status: 'online',
      lastSeenAt: DateTime.now().subtract(const Duration(minutes: 3)),
    );

LatestReading _reading(String channelId, String code, double value, String sensorId, String externalId, String label) =>
    LatestReading(
      channelId: channelId,
      channelTypeCode: code,
      value: value,
      tsOrigin: DateTime.now(),
      tsReceived: DateTime.now(),
      sensorId: sensorId,
      sensorExternalIdentifier: externalId,
      sensorLabel: label,
    );

final _readings = [
  _reading('tension', 'tension_soil', 18, 's1', 'A1', 'Tensiómetro'),
  _reading('ec', 'conductivity', 412, 's3', 'A3', 'Suelo plano'),
  _reading('hum', 'humidity_soil', 31.2, 's3', 'A3', 'Suelo plano'),
  _reading('temp', 'temperature_soil', 21.4, 's3', 'A3', 'Suelo plano'),
  // Datos de la propia estación (ADR-0008): iconos, no sensor.
  _reading('bat', 'battery_voltage', 3.451, 'st', '_device', ''),
  _reading('sig', 'signal_strength', -77, 'st', '_device', ''),
];

const _healthLabel = 'Cobertura buena (-77 dBm). Batería 3,45 V';

List<HistoryPoint> _history() => [
      for (var h = 23; h >= 0; h--)
        HistoryPoint(tsOrigin: DateTime.now().subtract(Duration(hours: h)), value: 20 + h % 5, min: null, max: null),
    ];

Future<void> _pump(WidgetTester tester, {required List<Gateway> gateways, Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/stations',
    routes: [
      GoRoute(
        path: '/stations',
        builder: (context, state) => const StationsScreen(),
        routes: [
          GoRoute(
            path: ':gatewayId',
            builder: (context, state) => StationDetailScreen(gatewayId: state.pathParameters['gatewayId']!),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stationsAcrossOrganizationsProvider.overrideWithValue(false),
        allGatewaysProvider.overrideWith((ref) async => gateways),
        stationGroupNamesProvider.overrideWith((ref) async => {'inst-1': (farm: 'Finca Norte', organization: null)}),
        gatewayLatestReadingsProvider.overrideWith((ref, gatewayId) async => _readings),
        stationSparklineProvider.overrideWith((ref, key) async => _history()),
        stationChannelHistoryProvider.overrideWith((ref, key) async => _history()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('B: en el móvil, resumen de las estaciones con su magnitud principal y sin lista para marcar', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N'), _gateway('gw-2', 'Estación Norte')]);

    expect(find.text('Estación WSC2-N'), findsOneWidget);
    expect(find.text('Estación Norte'), findsOneWidget);
    expect(find.byType(TextField), findsNothing); // sin buscador ni selección
    expect(find.text('Finca Norte'), findsNWidgets(2));
    expect(find.text('hace 3 min'), findsNWidgets(2));
    // Principal de cada sensor: tensión del tensiómetro y humedad de la sonda.
    expect(find.text('Tensión de suelo'), findsNWidgets(2));
    expect(find.text('Humedad de suelo'), findsNWidgets(2));
    expect(find.text('Conductividad'), findsNothing);
    expect(find.textContaining('31,2'), findsNWidgets(2));
    expect(find.text('Ver gráficas'), findsNWidgets(2));
    // Batería y cobertura, como iconos en cada tarjeta y fuera de las cifras.
    // La tarjeta entera es un botón: su etiqueta reúne la de los iconos con el resto.
    expect(find.bySemanticsLabel(RegExp(RegExp.escape(_healthLabel))), findsNWidgets(2));
    expect(find.text('2 sensores, 4 magnitudes'), findsNWidgets(2));
  });

  testWidgets('C: tocar una estación abre su pantalla con la principal ya dibujada', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N'), _gateway('gw-2', 'Estación Norte')]);

    await tester.tap(find.text('Estación WSC2-N'));
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Tensiómetro'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Suelo plano'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget); // tensión de suelo, sin tocar nada
    // Batería y cobertura: iconos en la barra de arriba, sin pestaña propia.
    expect(find.byType(Tab), findsNWidgets(2));
    expect(find.bySemanticsLabel(_healthLabel), findsOneWidget);
  });

  testWidgets('D: cada magnitud activada añade su propia gráfica, y quitarla la quita', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N'), _gateway('gw-2', 'Estación Norte')]);
    await tester.tap(find.text('Estación WSC2-N'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, 'Suelo plano'));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget); // humedad, la principal de la sonda
    expect(find.text('Humedad de suelo (%)'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Temperatura de suelo,')));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsNWidgets(2));
    expect(find.text('Temperatura de suelo (°C)'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Humedad de suelo,')));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Humedad de suelo (%)'), findsNothing);
  });

  testWidgets('la barra de lectura se queda arriba al bajar por la pantalla', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N')]);
    const pista = 'Toca o arrastra sobre la gráfica para leer los valores.';

    // Un sensor con tres gráficas abiertas: la pantalla ya no cabe de una vez.
    await tester.tap(find.widgetWithText(Tab, 'Suelo plano'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Temperatura de suelo,')));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('^Conductividad,')));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsNWidgets(3));

    final antes = tester.getTopLeft(find.text(pista)).dy;
    // Arrastre desde las cifras de arriba: sobre la gráfica, el dedo lee valores.
    await tester.dragFrom(const Offset(195, 160), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(find.text(pista), findsOneWidget);
    expect(tester.getTopLeft(find.text(pista)).dy, lessThan(antes));
    expect(find.byType(LineChart), findsNWidgets(3));
  });

  testWidgets('B: con una sola estación, el móvil abre directamente su pantalla', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N')]);

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Ver gráficas'), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('E: con el móvil girado, la estación enseña solo la gráfica, sin pestañas', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N')], size: const Size(844, 390));

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.textContaining('Gira el móvil'), findsNothing);
    // Solo la gráfica: los ajustes están guardados detrás del botón.
    expect(find.text('Estación WSC2-N'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Magnitudes'), findsNothing);
  });

  testWidgets('E: girado, la hoja de ajustes abre con sensor, rango y magnitudes, y se cierra', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N')], size: const Size(844, 390));

    await tester.tap(find.byTooltip('Sensor, rango y magnitudes'));
    await tester.pumpAndSettle();
    expect(find.text('Estación WSC2-N'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Tensiómetro'), findsOneWidget);
    expect(find.text('Rango'), findsOneWidget);
    expect(find.text('Magnitudes'), findsOneWidget);

    // Se cierra tocando fuera de la hoja, arriba del todo.
    await tester.tapAt(const Offset(422, 10));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('E: girado se cambia de sensor sin volver a poner el móvil derecho', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N')], size: const Size(844, 390));
    await tester.tap(find.byTooltip('Sensor, rango y magnitudes'));
    await tester.pumpAndSettle();

    expect(find.text('Tensión de suelo (cb)'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Suelo plano'));
    await tester.pumpAndSettle();
    expect(find.text('Humedad de suelo (%)'), findsOneWidget);
    expect(find.text('Tensión de suelo (cb)'), findsNothing);
  });

  testWidgets('E: girado también se eligen las magnitudes, en el mismo panel', (tester) async {
    await _pump(tester, gateways: [_gateway('gw-1', 'Estación WSC2-N')], size: const Size(844, 390));
    await tester.tap(find.byTooltip('Sensor, rango y magnitudes'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Suelo plano'));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget); // la principal, humedad

    // La lista del panel se arrastra para llegar a la última magnitud.
    await tester.drag(find.text('Magnitudes'), const Offset(0, -100));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel(RegExp('^Temperatura de suelo,')));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsNWidgets(2));
    expect(find.text('Temperatura de suelo (°C)'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Humedad de suelo,')));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Humedad de suelo (%)'), findsNothing);
  });

  testWidgets('un móvil girado no pasa a la vista de escritorio del resumen', (tester) async {
    await _pump(
      tester,
      gateways: [_gateway('gw-1', 'Estación WSC2-N'), _gateway('gw-2', 'Estación Norte')],
      size: const Size(844, 390),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ver gráficas'), findsWidgets);
  });

  testWidgets('en pantalla ancha, el mismo resumen que en el móvil', (tester) async {
    // Decisión del usuario (2026-09-18): se quitaron la lista para marcar
    // estaciones y la tarjeta de escritorio.
    await _pump(
      tester,
      gateways: [_gateway('gw-1', 'Estación WSC2-N'), _gateway('gw-2', 'Estación Norte')],
      size: const Size(1280, 900),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ver gráficas'), findsNWidgets(2));
    expect(find.text('Tensión de suelo'), findsNWidgets(2));
  });
}
