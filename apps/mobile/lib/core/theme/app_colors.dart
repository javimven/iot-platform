import 'package:flutter/material.dart';

/// Paleta de la plataforma (Etapa 14 — primer diseño real, 2026-08-04).
///
/// Nunca usar `Colors.red`/hexadecimales sueltos en una pantalla — todo
/// color visible viene de aquí (o de `Theme.of(context).colorScheme`, que
/// se construye a partir de estos mismos valores en `app_theme.dart`).
/// `brand` es el acento de marca; los semánticos (`ok`/`warn`/`critical`)
/// son un juego de color deliberadamente distinto, para que "todo bien" no
/// se confunda visualmente con el color corporativo.
abstract final class AppColors {
  // Modo claro
  static const ink = Color(0xFF1A2420);
  static const inkSoft = Color(0xFF4A5650);
  static const paper = Color(0xFFF7F8F5);
  static const paperRaised = Color(0xFFFFFFFF);
  static const line = Color(0xFFDCE3DD);
  static const brand = Color(0xFF1F6F5C);
  static const brandStrong = Color(0xFF154E41);

  // Modo oscuro
  static const inkDark = Color(0xFFE7ECE7);
  static const inkSoftDark = Color(0xFFAAB6B0);
  static const paperDark = Color(0xFF101513);
  static const paperRaisedDark = Color(0xFF182019);
  static const lineDark = Color(0xFF24302B);
  static const brandDark = Color(0xFF3CA98C);
  static const brandStrongDark = Color(0xFF5BC4A7);

  // Semántico — igual en claro/oscuro salvo ajuste de brillo para contraste.
  static const ok = Color(0xFF2B7FD1);
  static const okDark = Color(0xFF5B9FE0);
  static const warn = Color(0xFFC17A1E);
  static const warnDark = Color(0xFFD99A4E);
  static const critical = Color(0xFFC13A2E);
  static const criticalDark = Color(0xFFE2726A);

  // Texto dentro de un chip de estado (2026-09-16). Con el propio tono sobre su
  // fondo tintado no se llegaba a 4,5:1 (azul 3,4, ámbar 2,9 en claro; azul
  // 4,1 y rojo 3,9 en oscuro): el punto y el fondo siguen con el tono de
  // estado, y el texto usa una variante más oscura (claro) o más clara
  // (oscuro). Medido sobre `paperRaised`/`paper` y sus equivalentes oscuros:
  // todos por encima de 5:1.
  static const okInk = Color(0xFF1E63A6);
  static const okInkDark = Color(0xFF7FB4E8);
  static const warnInk = Color(0xFF8A5410);
  static const warnInkDark = Color(0xFFE0AC6C);
  static const criticalInk = Color(0xFFA4302A);
  static const criticalInkDark = Color(0xFFEC9791);

  // Menú lateral (Etapa 14 V2, BACKLOG.md #29) — cromo siempre oscuro,
  // independiente del tema claro/oscuro del resto de la app (como
  // Aigro/IKOS). Mismos valores de partida que paperDark/paperRaisedDark/
  // inkDark/inkSoftDark/lineDark/brandDark, pero como constantes propias:
  // son conceptos distintos que hoy comparten valor, no el mismo dato — un
  // cambio futuro de uno no debe mover el otro en silencio.
  static const sidebarBackground = Color(0xFF101513);
  static const sidebarSurfaceRaised = Color(0xFF182019);
  static const sidebarInk = Color(0xFFE7ECE7);
  static const sidebarInkSoft = Color(0xFFAAB6B0);
  static const sidebarLine = Color(0xFF24302B);
  static const sidebarBrand = Color(0xFF3CA98C);

  // Series de gráfica combinada (Estaciones, BACKLOG.md #30) — categórico,
  // distinto por tono de brand/ok/warn/critical (esos son de estado, no de
  // identidad de serie). Validado con la skill `dataviz`
  // (`scripts/validate_palette.js`, banda de luminosidad OKLCH, separación
  // CVD Machado-Oliveira-Fernandes, contraste ≥3:1) contra la superficie
  // real de cada modo — claro `#4F46E5`/`#C2185B` pasa todos los checks tal
  // cual; oscuro necesitó un tono más oscuro que el primer intento
  // (`#818CF8`/`#F06292`, L~0.68, fuera de la banda 0.48-0.67 en oscuro) —
  // `#6366F1`/`#EC4899` sí pasa completo.
  static const chartIndigo = Color(0xFF4F46E5);
  static const chartIndigoDark = Color(0xFF6366F1);
  static const chartRose = Color(0xFFC2185B);
  static const chartRoseDark = Color(0xFFEC4899);

  // Tercera serie (2026-09-16): las sondas de suelo miden tres magnitudes y
  // cada sensor lleva su propia gráfica. Ocre, comprobado con el mismo
  // criterio frente a las dos anteriores: L OKLCH 0.54 en claro y 0.67 en
  // oscuro (dentro de banda), contraste 5.1:1 y 5.4:1 con `paperRaised`/
  // `paperRaisedDark`, y distancia OKLab mínima entre pares de 7.4 en claro y
  // 12.9 en oscuro en el peor caso (deuteranopia en claro, tritanopia en
  // oscuro), simulando con Machado-Oliveira-Fernandes.
  static const chartOchre = Color(0xFF8A6A00);
  static const chartOchreDark = Color(0xFFBD8A0A);
}
