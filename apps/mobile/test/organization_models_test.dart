import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/organization/data/organization_models.dart';

void main() {
  group('OrganizationProfile.fromJson', () {
    test('parsea el perfil de una organización activa', () {
      final org = OrganizationProfile.fromJson({
        'id': 'org-1',
        'slug': 'acme',
        'name': 'Acme',
        'contactEmail': 'contact@acme.example',
        'status': 'active',
        'createdAt': '2026-01-01T00:00:00.000Z',
      });

      expect(org.name, 'Acme');
      expect(org.status, 'active');
    });
  });

  group('OrganizationFeature.fromJson', () {
    test('parsea una función activa', () {
      final feature = OrganizationFeature.fromJson({
        'featureCode': 'reports',
        'enabled': true,
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });

      expect(feature.featureCode, 'reports');
      expect(feature.enabled, isTrue);
    });
  });

  group('OrgChannelThreshold.fromJson', () {
    test('parsea un umbral con mínimo y máximo definidos', () {
      final threshold = OrgChannelThreshold.fromJson({
        'channelTypeCode': 'temperature_air',
        'defaultMin': 5,
        'defaultMax': 35.5,
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });

      expect(threshold.defaultMin, 5.0);
      expect(threshold.defaultMax, 35.5);
    });

    test('tolera mínimo/máximo nulos (sin definir)', () {
      final threshold = OrgChannelThreshold.fromJson({
        'channelTypeCode': 'humidity_soil',
        'defaultMin': null,
        'defaultMax': null,
        'updatedAt': '2026-01-01T00:00:00.000Z',
      });

      expect(threshold.defaultMin, isNull);
      expect(threshold.defaultMax, isNull);
    });
  });
}
