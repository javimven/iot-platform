import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/core/format/reading_format.dart';

/// Cifras de lecturas en español (BACKLOG.md #49, mejora G).
void main() {
  test('coma decimal', () {
    expect(formatReading(21.4), '21,4');
    expect(formatReading(412, decimals: 0), '412');
    expect(formatReading(3.456, decimals: 2), '3,46');
  });

  test('un negativo que se redondea a cero sale como 0, no como -0', () {
    // El tensiómetro en reposo marca -0,01 cb y se veía «-0.0 cb».
    expect(formatReading(-0.01), '0,0');
    expect(formatReading(-0.04, decimals: 0), '0');
  });

  test('los negativos de verdad conservan el signo', () {
    expect(formatReading(-3.25), '-3,3');
  });
}
