import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/alerts/data/alert_models.dart';

/// FUNCTIONAL_REQUIREMENTS.md §15: una alerta debe traer contexto legible
/// (nombre de instalación + causa), no solo IDs — y las fechas opcionales
/// (acknowledgedAt/resolvedAt) deben tolerar estar ausentes (alerta abierta).
void main() {
  group('Alert.fromJson', () {
    test('parsea una alerta de umbral abierta, sin acknowledgedAt/resolvedAt', () {
      final alert = Alert.fromJson({
        'id': 'alert-1',
        'alertType': 'threshold',
        'status': 'open',
        'openedAt': '2026-07-27T10:00:00.000Z',
        'acknowledgedAt': null,
        'resolvedAt': null,
        'details': {'value': 42.0, 'min': 0.0, 'max': 35.0},
        'installationName': 'Finca Norte',
        'channelTypeCode': 'temperature_air',
        'deviceName': null,
        'gatewayName': null,
      });

      expect(alert.status, 'open');
      expect(alert.acknowledgedAt, isNull);
      expect(alert.resolvedAt, isNull);
      expect(alert.installationName, 'Finca Norte');
      expect(alert.details?['value'], 42.0);
    });

    test('parsea una alerta de offline de gateway ya reconocida', () {
      final alert = Alert.fromJson({
        'id': 'alert-2',
        'alertType': 'offline',
        'status': 'acknowledged',
        'openedAt': '2026-07-27T09:00:00.000Z',
        'acknowledgedAt': '2026-07-27T09:05:00.000Z',
        'resolvedAt': null,
        'details': null,
        'installationName': 'Finca Sur',
        'channelTypeCode': null,
        'deviceName': null,
        'gatewayName': 'Gateway Sur',
      });

      expect(alert.status, 'acknowledged');
      expect(alert.acknowledgedAt, isNotNull);
      expect(alert.resolvedAt, isNull);
      expect(alert.gatewayName, 'Gateway Sur');
    });
  });
}
