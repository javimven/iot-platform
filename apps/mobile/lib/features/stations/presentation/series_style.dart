import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Color y trazo de la serie en la posición [index] de un sensor. El trazo
/// también cambia (continuo, discontinuo, punteado): las líneas se distinguen
/// sin depender solo del color (BACKLOG.md #49, mejora D).
({Color color, List<int>? dash}) seriesStyle(int index, {required bool isDark}) {
  const light = [AppColors.chartIndigo, AppColors.chartRose, AppColors.chartOchre];
  const dark = [AppColors.chartIndigoDark, AppColors.chartRoseDark, AppColors.chartOchreDark];
  const dashes = <List<int>?>[null, [8, 4], [2, 4]];
  final palette = isDark ? dark : light;
  if (index < palette.length) return (color: palette[index], dash: dashes[index]);
  return (color: isDark ? AppColors.inkSoftDark : AppColors.inkSoft, dash: const [6, 3, 2, 3]);
}

/// Muestra del trazo de una serie (para la leyenda y los interruptores).
class SeriesSwatch extends StatelessWidget {
  const SeriesSwatch({required this.color, required this.dash, this.width = 18, super.key});

  final Color color;
  final List<int>? dash;
  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, 4), painter: _SwatchPainter(color: color, dash: dash));
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({required this.color, required this.dash});

  final Color color;
  final List<int>? dash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    if (dash == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    var x = 0.0;
    var on = true;
    var i = 0;
    while (x < size.width) {
      final length = dash![i % dash!.length].toDouble();
      final end = (x + length).clamp(0.0, size.width);
      if (on) canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x = end;
      on = !on;
      i++;
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) => oldDelegate.color != color || oldDelegate.dash != dash;
}
