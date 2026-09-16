import '../../../core/format/reading_format.dart';

/// Formato compacto para las 2 marcas (mínimo/máximo) del eje Y de las
/// gráficas de Estaciones — sin decimales cuando el valor es entero, para
/// no alargar la etiqueta más de lo necesario.
String formatAxisValue(double value) {
  return formatReading(value, decimals: value == value.roundToDouble() ? 0 : 1);
}
