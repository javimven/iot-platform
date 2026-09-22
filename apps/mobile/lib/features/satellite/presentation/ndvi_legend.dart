import 'package:flutter/material.dart';

/// Escala de color del NDVI, la misma que usa el evalscript del backend
/// (`evalscripts.ts`): marrón para suelo desnudo y verde oscuro para
/// vegetación densa.
///
/// A propósito **no** lleva etiquetas del tipo "sano" o "estresado": qué NDVI
/// es bueno depende del cultivo, la fase, la densidad, el suelo y la época del
/// año, y poner un rótulo así sería inventarse agronomía. La leyenda dice qué
/// valor es cada color, y ya.
class NdviLegend extends StatelessWidget {
  const NdviLegend({super.key});

  static const _colores = [
    Color(0xFF8C6A4A),
    Color(0xFFBAA060),
    Color(0xFFA6BA60),
    Color(0xFF5C9642),
    Color(0xFF1A602E),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 10,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: _colores),
                  borderRadius: BorderRadius.all(Radius.circular(5)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('NDVI 0,0', style: theme.textTheme.labelSmall),
            Text('0,4', style: theme.textTheme.labelSmall),
            Text('0,8', style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
