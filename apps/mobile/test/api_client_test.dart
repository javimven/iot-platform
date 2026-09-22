import 'package:flutter_test/flutter_test.dart';
import 'package:iot_platform_app/core/api/api_client.dart';

/// Respuestas de las rutas que pueden no tener dato. Fallo real (2026-09-22):
/// NestJS manda un 200 con el cuerpo vacío cuando el controlador devuelve
/// `null`, dio lo entrega como `""`, y la app solo contemplaba `null`: en la
/// web compilada salía "Runtime type check failed" en la pantalla de Satélite.
void main() {
  test('el cuerpo vacío es "no hay dato", no un error', () {
    expect(comoObjetoOVacio(''), isNull);
    expect(comoObjetoOVacio('  '), isNull);
    expect(comoObjetoOVacio(null), isNull);
  });

  test('un objeto se devuelve tal cual', () {
    expect(comoObjetoOVacio(<String, dynamic>{'observationId': 'obs-1'}), {'observationId': 'obs-1'});
  });

  test('cualquier otra cosa es un contrato roto y se dice claro', () {
    expect(() => comoObjetoOVacio([1, 2]), throwsFormatException);
    expect(() => comoObjetoOVacio('texto'), throwsFormatException);
  });
}
