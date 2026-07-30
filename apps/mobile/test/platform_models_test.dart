import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/features/platform/data/platform_models.dart';

void main() {
  group('Feature.fromJson', () {
    test('parsea una función del catálogo', () {
      final feature = Feature.fromJson({'code': 'reports_pdf', 'label': 'Informes en PDF'});

      expect(feature.code, 'reports_pdf');
      expect(feature.label, 'Informes en PDF');
    });
  });
}
