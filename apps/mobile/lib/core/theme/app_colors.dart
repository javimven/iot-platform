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
}
