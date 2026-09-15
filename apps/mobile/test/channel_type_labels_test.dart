import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/readings/application/channel_type_labels.dart';

void main() {
  group('ChannelTypeLabels', () {
    test('devuelve la etiqueta y unidad conocidas para un tipo del catálogo', () {
      expect(ChannelTypeLabels.labelFor('temperature_air'), 'Temperatura ambiente');
      expect(ChannelTypeLabels.unitFor('temperature_air'), '°C');
    });

    test('un tipo de canal desconocido devuelve el propio código como etiqueta', () {
      expect(ChannelTypeLabels.labelFor('unknown_type'), 'unknown_type');
      expect(ChannelTypeLabels.unitFor('unknown_type'), '');
    });

    test('tipos de suelo de la estación WSC2-N (BACKLOG.md #44)', () {
      expect(ChannelTypeLabels.labelFor('temperature_soil'), 'Temperatura de suelo');
      expect(ChannelTypeLabels.unitFor('temperature_soil'), '°C');
      expect(ChannelTypeLabels.labelFor('tension_soil'), 'Tensión de suelo');
      expect(ChannelTypeLabels.unitFor('tension_soil'), 'cb');
    });
  });
}
