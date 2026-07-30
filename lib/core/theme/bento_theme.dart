import 'package:flutter/material.dart';

import 'bento_ink.dart';

// CONTRATO DE DIRECCION (ver DESIGN.md en la raiz del repo).
//
// THESIS: la pantalla es UNA bandeja de una sola pieza con el contenido
// hundido en pozos tallados, no una pagina de tarjetas flotando. Rechaza el
// modelo de Material 3 donde importancia = elevacion = superficie mas clara.
//
// OWN-WORLD: laca oscura saturada como marco continuo — borde exterior 24,
// paredes interiores compartidas 12, radio exterior 20 contra radio de pozo
// 4. Cada pozo lleva cresta de pared iluminada de 1px y sombra de contacto
// en su borde superior. Un solo acento (oro de laca) para accion primaria y
// seleccion. Cero BoxShadow en celdas.
//
// STORY: la registradora distingue de un golpe que pozo es que, por tamano y
// por hueco; el marco nunca compite con los datos.
//
// FIRST VIEWPORT: rail izquierdo como banda de bandeja, grid de productos
// como pozos iguales, total en un pozo grande y propio.
//
// FORM: mundo fijado por el usuario (bento), re-renderizado desde su rango
// material completo. No hubo tirada de concepto porque el mundo no se
// reemplaza: la falla anterior fue de ejecucion, no de seleccion.

/// Tokens de espaciado. Unidad base 8 (regla de la skill de diseno bento:
/// solo multiplos, nunca valores ad hoc).
class BentoSpacing {
  const BentoSpacing._();

  static const double unidad = 8;
  static const double gapCelda = unidad * 2; // 16
  static const double gapGrupo = unidad * 3; // 24
  static const double paddingCelda = unidad * 2; // 16
  static const double paddingCeldaGrande = unidad * 3; // 24

  /// Ancho de la pared compartida entre dos pozos adyacentes. NO es "el
  /// fondo asomandose" — es material de bandeja (DESIGN.md, regla 2), asi
  /// que dos pozos vecinos comparten UNA sola pared de este ancho.
  static const double pared = unidad * 1.5; // 12

  /// Borde exterior de la bandeja. Mas grueso que la pared interior, como el
  /// labio de una bandeja real.
  static const double rim = unidad * 3; // 24
}

class BentoRadius {
  const BentoRadius._();

  /// Interior rectilineo: los compartimentos de una bandeja no son
  /// rectangulos redondeados sueltos.
  static const double pozo = 4;

  /// Exterior suave, como el canto de la bandeja.
  static const double bandeja = 20;
}

/// Duracion del feedback tactil (onda al presionar).
const Duration bentoFeedbackTactilDuracion = Duration(milliseconds: 200);

/// Objetivo tactil minimo. Corre en tablet en el mostrador (escena de uso
/// confirmada), asi que todo lo tocable respeta esto — DESIGN.md, regla 6.
const double bentoObjetivoTactilMin = 48;

/// Acabados de laca disponibles. Antes eran tres grises desaturados, que
/// fueron causa directa del aspecto generico: no habia color en ninguna
/// parte. Se conserva la intencion de la decision 0020 (pocos acentos,
/// hardcodeados, coherentes) y se corrige el material — ahora cada opcion es
/// un acabado de laca real, no un matiz de gris.
///
/// Los nombres viejos (`grisAzulado`...) ya no existen: `PreferenciasNotifier`
/// resuelve el acento guardado con `orElse` al default, asi que una
/// preferencia vieja cae sola al primer acabado sin migracion.
enum AcentoTinte { verdeLaca, negroLaca, caoba }

/// Tokens de material que `ColorScheme` no tiene como expresar: la bandeja
/// (el plano continuo), la cresta de pared iluminada y la sombra de contacto
/// dentro del pozo.
///
/// El mapeo deliberado con `ColorScheme`: `surface` es el POZO, no la
/// bandeja, para que el texto por defecto de cualquier widget caiga correcto
/// sobre el fondo de contenido. La bandeja va en `scaffoldBackgroundColor` y
/// en estos tokens, y se usa explicitamente en el cromo (rail, paredes).
@immutable
class BentoLaca extends ThemeExtension<BentoLaca> {
  const BentoLaca({
    required this.bandeja,
    required this.paredCresta,
    required this.pozo,
    required this.pozoContacto,
    required this.textoEnBandeja,
    required this.textoAtenuadoEnBandeja,
  });

  /// El plano continuo de la bandeja: fondo de pantalla y material de las
  /// paredes entre pozos.
  final Color bandeja;

  /// Cresta iluminada de la pared, 1px en el borde del pozo. Es la senal
  /// PRIMARIA de tallado — verificada >=3:1 contra la bandeja en los 3
  /// acabados y los 2 modos, porque en modo oscuro el escalon de valor
  /// bandeja/pozo no puede llegar a 3:1 (rango de luminancia comprimido).
  /// Ver DESIGN.md, regla 1.
  final Color paredCresta;

  /// Fondo del pozo: la superficie donde vive el contenido.
  final Color pozo;

  /// Sombra que la pared proyecta hacia dentro del pozo, en su borde
  /// superior. Es un degradado corto y duro, nunca una sombra suave: bajo sol
  /// directo las sombras de baja opacidad desaparecen.
  final Color pozoContacto;

  final Color textoEnBandeja;
  final Color textoAtenuadoEnBandeja;

  @override
  BentoLaca copyWith({
    Color? bandeja,
    Color? paredCresta,
    Color? pozo,
    Color? pozoContacto,
    Color? textoEnBandeja,
    Color? textoAtenuadoEnBandeja,
  }) {
    return BentoLaca(
      bandeja: bandeja ?? this.bandeja,
      paredCresta: paredCresta ?? this.paredCresta,
      pozo: pozo ?? this.pozo,
      pozoContacto: pozoContacto ?? this.pozoContacto,
      textoEnBandeja: textoEnBandeja ?? this.textoEnBandeja,
      textoAtenuadoEnBandeja: textoAtenuadoEnBandeja ?? this.textoAtenuadoEnBandeja,
    );
  }

  @override
  BentoLaca lerp(BentoLaca? other, double t) {
    if (other == null) return this;
    return BentoLaca(
      bandeja: Color.lerp(bandeja, other.bandeja, t)!,
      paredCresta: Color.lerp(paredCresta, other.paredCresta, t)!,
      pozo: Color.lerp(pozo, other.pozo, t)!,
      pozoContacto: Color.lerp(pozoContacto, other.pozoContacto, t)!,
      textoEnBandeja: Color.lerp(textoEnBandeja, other.textoEnBandeja, t)!,
      textoAtenuadoEnBandeja: Color.lerp(textoAtenuadoEnBandeja, other.textoAtenuadoEnBandeja, t)!,
    );
  }
}

/// Atajo para leer los tokens de laca desde un widget.
BentoLaca lacaDe(BuildContext context) => Theme.of(context).extension<BentoLaca>()!;

// --- Paleta de autoria propia -----------------------------------------------
// Nada de `ColorScheme.fromSeed`: el algoritmo tonal de Material 3 codifica
// elevacion-como-claridad, que es exactamente lo contrario de un pozo, y fue
// la causa raiz del aspecto por defecto (DESIGN.md, regla 5).
//
// Contraste verificado con la formula WCAG sobre los pares realmente usados
// (texto >=4.5:1; bordes de superficie >=3:1 por WCAG 1.4.11). La prueba
// `test/contraste_laca_test.dart` recalcula estos numeros contra estas
// mismas constantes, para que no se degraden en una edicion futura.

// Bandeja y cresta por acabado. La cresta de cada acabado esta ajustada al
// minimo que cumple 3:1 contra SU bandeja, no copiada entre acabados.
const _bandejaClara = {
  AcentoTinte.verdeLaca: Color(0xFF1F2A24),
  AcentoTinte.negroLaca: Color(0xFF22201D),
  AcentoTinte.caoba: Color(0xFF2B1D1A),
};
const _crestaClara = {
  AcentoTinte.verdeLaca: Color(0xFF647A69), // 3.20:1
  AcentoTinte.negroLaca: Color(0xFF6E6B65), // 3.06:1
  AcentoTinte.caoba: Color(0xFF7E665E), // 3.05:1
};
const _bandejaOscura = {
  AcentoTinte.verdeLaca: Color(0xFF0C110D),
  AcentoTinte.negroLaca: Color(0xFF0F0E0C),
  AcentoTinte.caoba: Color(0xFF150E0C),
};
const _crestaOscura = {
  AcentoTinte.verdeLaca: Color(0xFF5A6E5F), // 3.48:1
  AcentoTinte.negroLaca: Color(0xFF646059), // 3.09:1
  AcentoTinte.caoba: Color(0xFF745C54), // 3.09:1
};

// Pozo y texto: compartidos por los 3 acabados. El contenido no cambia de
// temperatura segun el acabado de la bandeja — solo el marco lo hace.
const _pozoClaro = Color(0xFFF4F1EA);
const _pozoContactoClaro = Color(0xFFD8D2C4);
const _textoEnPozoClaro = Color(0xFF221F1A); // 14.56:1
const _textoSecundarioEnPozoClaro = Color(0xFF6B655A); // 5.12:1

const _pozoOscuro = Color(0xFF2B2926);
const _pozoContactoOscuro = Color(0xFF1B1917);
const _textoEnPozoOscuro = Color(0xFFE8E4DA);
const _textoSecundarioEnPozoOscuro = Color(0xFF9C968C);

const _textoEnBandeja = Color(0xFFE8E4DA);
const _textoAtenuadoEnBandejaClara = Color(0xFFA8B0A6); // 6.66:1
const _textoAtenuadoEnBandejaOscura = Color(0xFF8C948C);

// Oro de laca: el unico acento. Solo accion primaria, seleccion actual e
// indicador de estado — nunca decoracion, nunca en estado inactivo.
const _oroClaro = Color(0xFFC8892F); // texto #221F1A encima: 5.53:1
const _oroOscuro = Color(0xFFD9A24A); // texto #1A1712 encima: 7.84:1
const _sobreOroClaro = Color(0xFF221F1A);
const _sobreOroOscuro = Color(0xFF1A1712);

const _rojoClaro = Color(0xFF9E2F1B);
const _rojoOscuro = Color(0xFFF0A08C);
const _sobreRojoClaro = Color(0xFFFFFFFF);
const _sobreRojoOscuro = Color(0xFF2A0D07);

BentoLaca _lacaDe(AcentoTinte acento, Brightness brillo) {
  final claro = brillo == Brightness.light;
  return BentoLaca(
    bandeja: (claro ? _bandejaClara : _bandejaOscura)[acento]!,
    paredCresta: (claro ? _crestaClara : _crestaOscura)[acento]!,
    pozo: claro ? _pozoClaro : _pozoOscuro,
    pozoContacto: claro ? _pozoContactoClaro : _pozoContactoOscuro,
    textoEnBandeja: _textoEnBandeja,
    textoAtenuadoEnBandeja: claro ? _textoAtenuadoEnBandejaClara : _textoAtenuadoEnBandejaOscura,
  );
}

ColorScheme _esquemaDe(AcentoTinte acento, Brightness brillo) {
  final claro = brillo == Brightness.light;
  final pozo = claro ? _pozoClaro : _pozoOscuro;
  final textoEnPozo = claro ? _textoEnPozoClaro : _textoEnPozoOscuro;
  final oro = claro ? _oroClaro : _oroOscuro;

  return ColorScheme(
    brightness: brillo,
    primary: oro,
    onPrimary: claro ? _sobreOroClaro : _sobreOroOscuro,
    primaryContainer: oro,
    onPrimaryContainer: claro ? _sobreOroClaro : _sobreOroOscuro,
    secondary: (claro ? _crestaClara : _crestaOscura)[acento]!,
    onSecondary: _textoEnBandeja,
    error: claro ? _rojoClaro : _rojoOscuro,
    onError: claro ? _sobreRojoClaro : _sobreRojoOscuro,
    // `surface` es el POZO, no la bandeja: asi el texto por defecto de
    // cualquier widget cae legible sobre el fondo de contenido.
    surface: pozo,
    onSurface: textoEnPozo,
    onSurfaceVariant: claro ? _textoSecundarioEnPozoClaro : _textoSecundarioEnPozoOscuro,
    // Toda la escalera de contenedores de M3 apunta al mismo pozo: neutraliza
    // el "mas elevado = mas claro" para que ningun widget derive solo hacia
    // un tono mas claro y vuelva a parecer una tarjeta flotante.
    surfaceContainerLowest: pozo,
    surfaceContainerLow: pozo,
    surfaceContainer: pozo,
    surfaceContainerHigh: pozo,
    surfaceContainerHighest: pozo,
    // La cresta es literalmente el contorno del pozo.
    outline: (claro ? _crestaClara : _crestaOscura)[acento]!,
    outlineVariant: claro ? _pozoContactoClaro : _pozoContactoOscuro,
  );
}

/// Escala tipografica modular sobre la base de Material 3.
///
/// Guia de uso:
/// - Hero de una pantalla (ej. total del dia en Reportes) -> `displaySmall`
/// - Titulo de seccion destacada -> `headlineSmall` (24)
/// - Subtitulo -> `titleLarge` (20)
/// - Texto de contenido normal -> `bodyLarge` (16, base)
/// - Texto secundario / metadata -> `bodyMedium` (14)
/// - Etiqueta de boton -> `labelLarge` (14)
/// - Texto auxiliar chico (fecha, nota) -> `bodySmall` (12)
TextTheme _escalaTipografica(TextTheme base) {
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(fontSize: 40, fontWeight: FontWeight.w600),
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    titleLarge: base.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w500),
  );
}

ThemeData buildBentoTheme(AcentoTinte acento, {Brightness brightness = Brightness.light}) {
  final scheme = _esquemaDe(acento, brightness);
  final laca = _lacaDe(acento, brightness);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  return base.copyWith(
    extensions: [laca],
    textTheme: _escalaTipografica(base.textTheme),
    // La bandeja es el plano de fondo de toda pantalla.
    scaffoldBackgroundColor: laca.bandeja,
    splashFactory: BentoGrainSplash.splashFactory,
    // Sin elevacion ni sombra: la profundidad la da la cresta, no una sombra
    // proyectada (DESIGN.md, regla 1).
    cardTheme: CardThemeData(
      color: laca.pozo,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.pozo)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: laca.pozo,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.bandeja)),
      insetPadding: const EdgeInsets.all(BentoSpacing.gapGrupo),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(BentoRadius.pozo)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad * 1.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, bentoObjetivoTactilMin),
        padding: const EdgeInsets.symmetric(
          horizontal: BentoSpacing.paddingCeldaGrande,
          vertical: BentoSpacing.paddingCelda,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.pozo)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, bentoObjetivoTactilMin),
        padding: const EdgeInsets.symmetric(
          horizontal: BentoSpacing.paddingCelda,
          vertical: BentoSpacing.unidad,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BentoRadius.pozo)),
      minVerticalPadding: BentoSpacing.unidad * 1.5,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad,
      ),
    ),
    appBarTheme: AppBarThemeData(
      centerTitle: false,
      elevation: 0,
      backgroundColor: laca.bandeja,
      foregroundColor: laca.textoEnBandeja,
    ),
  );
}
