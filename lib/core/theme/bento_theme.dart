import 'package:flutter/material.dart';

/// Tokens del sistema visual bento — ver docs/pantallas/prototipos-ascii.md.
/// Cambiar valores aqui, no ad-hoc en cada widget (regla de espaciado
/// consistente de la skill de diseno bento).
class BentoSpacing {
  const BentoSpacing._();

  static const double unidad = 8;
  static const double gapCelda = unidad * 2; // 16
  static const double gapGrupo = unidad * 3; // 24
  static const double paddingCelda = unidad * 2; // 16
  static const double paddingCeldaGrande = unidad * 3; // 24
}

class BentoRadius {
  const BentoRadius._();

  static const double celda = 12;
  static const double hero = 16;
}

/// Duracion del feedback tactil (onda al presionar) — ver
/// docs/pantallas/prototipos-ascii.md#feedback-tactil. Un poco mas lento
/// que un parpadeo, buscando agilidad.
const Duration bentoFeedbackTactilDuracion = Duration(milliseconds: 200);

ThemeData buildBentoTheme() {
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.teal,
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BentoRadius.celda),
      ),
      margin: EdgeInsets.zero,
    ),
  );
}
