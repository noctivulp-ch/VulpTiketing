import 'package:flutter/material.dart';

import 'bento_ink.dart';

// CONTRATO DE DIRECCION (ver DESIGN.md en la raiz del repo).
//
// THESIS: la pantalla es UNA bandeja de una sola pieza con el contenido
// hundido en pozos tallados, no una pagina de tarjetas flotando. Rechaza el
// modelo de Material 3 donde importancia = elevacion = superficie mas clara.
//
// OWN-WORLD: dos lacas completas, una por modo, tomadas de la construccion
// real de las cajas de las referencias (negras por fuera, ROJAS por dentro):
// oscuro = marco negro + pozos rojos + metal; claro = su reflejo, marco
// blanco + pozos verdes + metal. Marco continuo con borde exterior 24,
// paredes compartidas 12, radio exterior 20 contra radio de pozo 4. Cada pozo
// lleva borde de 1px y sombra de contacto arriba. El metal (oro/cobre/peltre)
// es el unico acento y solo marca accion primaria y seleccion. Cero BoxShadow.
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

/// Metal del acento. Sobre laca, el pan de metal tradicional es oro, pero
/// cobre y peltre tambien lo son — asi que el ajuste configurable de la
/// decision 0020 pasa a elegir el METAL, no el color de la laca.
///
/// El reparto de responsabilidades es lo importante: el MODO (claro/oscuro)
/// determina la laca completa (blanco-verde u oscuro-rojo) y el metal es
/// ortogonal, igual en los dos modos. Antes el ajuste variaba la bandeja, lo
/// que chocaba con que el modo tambien la variara.
///
/// Los nombres viejos no existen mas: `PreferenciasNotifier` resuelve el
/// acento guardado con `orElse` al default, asi que una preferencia vieja cae
/// sola al primer metal sin migracion.
enum AcentoTinte { oro, cobre, peltre }

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

// Dos lacas completas, una por modo. La caja bento fisica no cambia de color,
// pero una app si — y sostener que la bandeja siguiera oscura en modo claro
// hacia que los dos modos se vieran casi iguales (parecia un "modo contraste",
// no un modo claro) y era la causa raiz de la mala legibilidad: todo lo que
// caia sobre la bandeja heredaba color de texto de pozo.
//
// El par sale de la construccion real de las cajas de laca de las referencias
// (docs/pantallas/referencias-visuales/): NEGRAS por fuera y ROJAS por dentro.
// El modo claro es su reflejo: BLANCA por fuera, VERDE por dentro.
//
//   oscuro -> negro (marco) + rojo (pozos) + metal
//   claro  -> blanco (marco) + verde (pozos) + metal

// Marco negro, interior de laca roja.
const _bandejaOscura = Color(0xFF14100E);
const _pozoOscuro = Color(0xFF3A1E1B);
const _pozoContactoOscuro = Color(0xFF2D110E);
const _bordePozoOscuro = Color(0xFF8E675A); // 3.82:1 vs bandeja, 3.07:1 vs pozo
const _textoEnPozoOscuro = Color(0xFFF5EAE2); // 12.85:1
const _textoSecundarioEnPozoOscuro = Color(0xFFCBA99C); // 7.02:1
const _textoEnBandejaOscura = Color(0xFFEDE4DC); // 15.07:1
const _textoAtenuadoEnBandejaOscura = Color(0xFFA99C93); // 7.08:1

// Marco blanco, interior de laca verde.
const _bandejaClara = Color(0xFFF8F7F2);
const _pozoClaro = Color(0xFFD7E1D3);
const _pozoContactoClaro = Color(0xFFC4D2BF);
const _bordePozoClaro = Color(0xFF5A6E58); // 5.14:1 vs bandeja, 4.10:1 vs pozo
const _textoEnPozoClaro = Color(0xFF1E2A1C); // 11.12:1
const _textoSecundarioEnPozoClaro = Color(0xFF495747); // 5.70:1
const _textoEnBandejaClara = Color(0xFF232522); // 14.40:1
const _textoAtenuadoEnBandejaClara = Color(0xFF55584F); // 6.76:1

// Metal del acento, ortogonal al modo. Cada uno verificado como texto sobre
// bandeja Y sobre pozo, y como relleno con su propio color de texto encima.
const _metales = {
  AcentoTinte.oro: (claro: Color(0xFF7A4F0E), oscuro: Color(0xFFD9A54A)),
  AcentoTinte.cobre: (claro: Color(0xFF7E3F16), oscuro: Color(0xFFD98E5E)),
  AcentoTinte.peltre: (claro: Color(0xFF4F5450), oscuro: Color(0xFFC6C4BC)),
};
const _sobreMetalClaro = Color(0xFFFFFFFF);
const _sobreMetalOscuro = {
  AcentoTinte.oro: Color(0xFF241A0C),
  AcentoTinte.cobre: Color(0xFF2A1408),
  AcentoTinte.peltre: Color(0xFF1E1D1A),
};

const _rojoErrorClaro = Color(0xFF9E2F1B);
const _rojoErrorOscuro = Color(0xFFF0A08C);
const _sobreErrorClaro = Color(0xFFFFFFFF);
const _sobreErrorOscuro = Color(0xFF2A0D07);

BentoLaca _lacaDe(Brightness brillo) {
  final claro = brillo == Brightness.light;
  return BentoLaca(
    bandeja: claro ? _bandejaClara : _bandejaOscura,
    paredCresta: claro ? _bordePozoClaro : _bordePozoOscuro,
    pozo: claro ? _pozoClaro : _pozoOscuro,
    pozoContacto: claro ? _pozoContactoClaro : _pozoContactoOscuro,
    textoEnBandeja: claro ? _textoEnBandejaClara : _textoEnBandejaOscura,
    textoAtenuadoEnBandeja: claro ? _textoAtenuadoEnBandejaClara : _textoAtenuadoEnBandejaOscura,
  );
}

ColorScheme _esquemaDe(AcentoTinte acento, Brightness brillo) {
  final claro = brillo == Brightness.light;
  final pozo = claro ? _pozoClaro : _pozoOscuro;
  final textoEnPozo = claro ? _textoEnPozoClaro : _textoEnPozoOscuro;
  final metal = claro ? _metales[acento]!.claro : _metales[acento]!.oscuro;
  final sobreMetal = claro ? _sobreMetalClaro : _sobreMetalOscuro[acento]!;

  return ColorScheme(
    brightness: brillo,
    primary: metal,
    onPrimary: sobreMetal,
    primaryContainer: metal,
    onPrimaryContainer: sobreMetal,
    secondary: claro ? _bordePozoClaro : _bordePozoOscuro,
    onSecondary: claro ? _bandejaClara : _textoEnBandejaOscura,
    error: claro ? _rojoErrorClaro : _rojoErrorOscuro,
    onError: claro ? _sobreErrorClaro : _sobreErrorOscuro,
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
    outline: claro ? _bordePozoClaro : _bordePozoOscuro,
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
  final laca = _lacaDe(brightness);
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
