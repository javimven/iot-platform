import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/directory/data/directory_models.dart';

/// DATA_MODEL.md §4: `lastSeenAt` es nulo hasta la primera conexión — el
/// modelo debe tolerar su ausencia sin lanzar.
void main() {
  group('Gateway.fromJson', () {
    test('parsea un gateway sin conexión todavía (lastSeenAt nulo)', () {
      final gateway = Gateway.fromJson({
        'id': 'gw-1',
        'installationId': 'inst-1',
        'name': 'Gateway Norte',
        'connectivityType': 'lora_concentrator',
        'status': 'not_provisioned',
        'lastSeenAt': null,
      });

      expect(gateway.name, 'Gateway Norte');
      expect(gateway.lastSeenAt, isNull);
    });

    test('parsea un gateway ya conectado', () {
      final gateway = Gateway.fromJson({
        'id': 'gw-2',
        'installationId': 'inst-1',
        'name': 'Gateway Sur',
        'connectivityType': 'nbiot_direct',
        'status': 'online',
        'lastSeenAt': '2026-07-27T09:00:00.000Z',
      });

      expect(gateway.status, 'online');
      expect(gateway.lastSeenAt, isNotNull);
    });
  });

  group('Channel.fromJson', () {
    test('parsea un canal sin umbral propio', () {
      final channel = Channel.fromJson({
        'id': 'ch-1',
        'channelTypeCode': 'temperature_air',
        'alertThresholdMin': null,
        'alertThresholdMax': null,
      });

      expect(channel.alertThresholdMin, isNull);
      expect(channel.alertThresholdMax, isNull);
    });
  });
}
