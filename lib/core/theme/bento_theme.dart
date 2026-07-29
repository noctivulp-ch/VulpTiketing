import 'package:flutter/material.dart';

import 'bento_ink.dart';

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

/// Escala tipografica modular (skill `typography-scale`) sobre la base de
/// Material 3 — la mayoria de los tamanos pedidos ya coinciden con los
/// defaults de M3 (bodySmall 12 = caption, bodyMedium 14 = body pequeno,
/// bodyLarge 16 = body base, headlineSmall 24 = heading3, headlineLarge 32 =
/// heading2), asi que solo se ajustan los dos roles que M3 no cubre tal
/// cual: subtitulo (titleLarge, pedido en 20 pero M3 trae 22) y hero/
/// heading1 (no existe un rol de 40 en M3; se reutiliza displaySmall).
///
/// Guia de uso (para no memorizarla, consultar aqui):
/// - Hero de una pantalla (ej. total del dia en Reportes) -> `displaySmall`
/// - Titulo de dialogo o seccion destacada -> `headlineSmall` (24)
/// - Subtitulo -> `titleLarge` (20)
/// - Texto de contenido normal -> `bodyLarge` (16, base)
/// - Texto secundario / metadata -> `bodyMedium` (14)
/// - Etiqueta de boton -> `labelLarge` (14, ya viene medium por defecto)
/// - Texto auxiliar chico (fecha, nota) -> `bodySmall` (12)
TextTheme _escalaTipografica(TextTheme base) {
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(fontSize: 40, fontWeight: FontWeight.w600),
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    titleLarge: base.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w500),
  );
}

/// [brightness] construye la variante clara u oscura del mismo acento — ver
/// `Preferencias.modoTema` / `lib/app.dart` (`theme`/`darkTheme`).
/// `ColorScheme.fromSeed` genera un esquema oscuro coherente con la misma
/// semilla desaturada sin necesitar una paleta aparte para modo oscuro.
ThemeData buildBentoTheme(AcentoTinte acento, {Brightness brightness = Brightness.light}) {
  // `ColorScheme.fromSeed` con variante neutral: escala de grises por
  // jerarquia con un matiz del color semilla, en vez del esquema vivo/
  // saturado por defecto de Material 3.
  //
  // Contraste verificado (skill `color-system`, formula WCAG via
  // `Color.computeLuminance()`) para los pares de texto/fondo realmente
  // usados en la app, en los 3 acentos (modo claro): onSurface/surface
  // ~16:1, onSurfaceVariant/surface ~9:1, onPrimaryContainer/
  // primaryContainer ~7.25:1, onPrimary/primary ~6.45:1 — todos superan
  // holgadamente AAA (7:1), no solo el minimo AA (4.5:1) pedido por la
  // skill. El algoritmo tonal de M3 mantiene las mismas garantias de
  // contraste en la variante oscura (invierte las tonalidades, no las
  // relaciones de contraste).
  final scheme = ColorScheme.fromSeed(
    seedColor: _semillaDe(acento),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  return base.copyWith(
    textTheme: _escalaTipografica(base.textTheme),
    // Ripple con textura granulada (0020 / prototipos-ascii.md#feedback-
    // tactil) en vez del splash liso por defecto — una sola vez aqui,
    // beneficia a todo InkWell/Card/ListTile de la app automaticamente.
    splashFactory: BentoGrainSplash.splashFactory,
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.celda)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.hero)),
      insetPadding: const EdgeInsets.all(BentoSpacing.gapGrupo),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(BentoRadius.celda)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad * 1.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: BentoSpacing.paddingCeldaGrande,
          vertical: BentoSpacing.paddingCelda,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.celda)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: BentoSpacing.paddingCelda,
          vertical: BentoSpacing.unidad,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.celda)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad,
      ),
    ),
    appBarTheme: const AppBarThemeData(centerTitle: false, elevation: 0),
  );
}
