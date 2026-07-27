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
  };

  static String labelFor(String code) => _labels[code]?.$1 ?? code;

  static String unitFor(String code) => _labels[code]?.$2 ?? '';
}
