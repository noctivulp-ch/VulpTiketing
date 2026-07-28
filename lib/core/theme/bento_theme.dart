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

/// Tintes de acento disponibles (decision de iconografia — ver
/// docs/pantallas/iconografia.md). Deliberadamente pocos y todos de baja
/// saturacion: la jerarquia visual la da la escala de grises, el acento es
/// solo un matiz, nunca color vivo protagonico.
enum AcentoTinte { grisAzulado, grisVerdoso, grisCafe }

Color _semillaDe(AcentoTinte acento) {
  switch (acento) {
    case AcentoTinte.grisAzulado:
      return const Color(0xFF64748B);
    case AcentoTinte.grisVerdoso:
      return const Color(0xFF6B7A6E);
    case AcentoTinte.grisCafe:
      return const Color(0xFF7A6F63);
  }
}

ThemeData buildBentoTheme(AcentoTinte acento) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _semillaDe(acento),
    // Neutral: esquema de color que se mantiene cerca del gris con solo un
    // matiz del color semilla, en vez del esquema vivo/saturado por
    // defecto de Material 3 — es la pieza que produce "escala de grises
    // por jerarquia con un matiz desaturado" pedido por el usuario.
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BentoRadius.celda),
      ),
      margin: EdgeInsets.zero,
    ),
  );
}
