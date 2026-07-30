/// Espejo de `Feature` (OPENAPI.yaml, `GET /platform/features`) — catálogo
/// completo, independiente de qué organización tenga cada una activada
/// (`BACKLOG.md` #17: sin esto, el editor de funciones de una organización
/// que nunca activó ninguna no tenía nada que mostrar).
class Feature {
  final String code;
  final String label;

  const Feature({required this.code, required this.label});

  factory Feature.fromJson(Map<String, dynamic> json) => Feature(
        code: json['code'] as String,
        label: json['label'] as String,
      );
}
