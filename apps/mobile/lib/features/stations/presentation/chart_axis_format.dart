/// Formato compacto para las 2 marcas (mínimo/máximo) del eje Y de las
/// gráficas de Estaciones — sin decimales cuando el valor es entero, para
/// no alargar la etiqueta más de lo necesario.
String formatAxisValue(double value) {
  return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}
