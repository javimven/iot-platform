import 'dart:ui' show FontFeature;

/// Cifras de lecturas tal como se leen en español: coma decimal y sin «-0,0»
/// cuando un valor negativo muy pequeño se redondea a cero (el tensiómetro
/// en reposo marca −0,01 cb y salía «-0.0 cb»).
String formatReading(double value, {int decimals = 1}) {
  var fixed = value.toStringAsFixed(decimals);
  if (fixed.startsWith('-') && double.parse(fixed) == 0) {
    fixed = fixed.substring(1);
  }
  return fixed.replaceAll('.', ',');
}

/// Números de ancho fijo: las cifras no bailan al actualizarse y alinean en
/// columna (BACKLOG.md #49, mejora G).
const tabularFigures = [FontFeature.tabularFigures()];
