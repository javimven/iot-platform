/// Etiquetas de presentación para el catálogo de `channel_types` (prisma/seed.ts,
/// FUNCTIONAL_REQUIREMENTS.md §8). Solo texto/unidad para mostrar — el valor
/// real y su validez ya los decide el backend, esto no es lógica de negocio.
class ChannelTypeLabels {
  static const Map<String, (String label, String unit)> _labels = {
    'temperature_air': ('Temperatura ambiente', '°C'),
    'humidity_air': ('Humedad relativa', '%'),
    'humidity_soil': ('Humedad de suelo', '%'),
    'conductivity': ('Conductividad', 'µS/cm'),
    'tank_level': ('Nivel de depósito', '%'),
    'battery': ('Batería', '%'),
    'signal_strength': ('Señal', 'dBm'),
    'precipitation': ('Precipitación', 'mm'),
    'temperature_soil': ('Temperatura de suelo', '°C'),
    'tension_soil': ('Tensión de suelo', 'cb'),
  };

  static String labelFor(String code) => _labels[code]?.$1 ?? code;

  static String unitFor(String code) => _labels[code]?.$2 ?? '';

  /// Espejo de `channel_types.default_aggregation` (`prisma/seed.ts`) — solo
  /// `precipitation` es `sum` hoy, el resto `average`. Necesario en cliente
  /// para que la gráfica combinada de Estaciones (BACKLOG.md #30) sepa qué
  /// canal dibujar como barra y cuál como línea, sin pedirlo al backend.
  static String aggregationFor(String code) => code == 'precipitation' ? 'sum' : 'average';
}
