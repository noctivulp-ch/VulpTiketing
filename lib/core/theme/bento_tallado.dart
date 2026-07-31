import 'package:flutter/material.dart';

/// Tallado: el glifo se lee grabado en su superficie en vez de apoyado encima.
///
/// Calibrado por el usuario en el banco de pruebas (`test_driver/sandbox.dart`)
/// y exportado el 2026-07-30: profundidad 1.25, luz 0.70, sombra 0.65 — una
/// incision poco profunda con el canto brillante, mas "metal pulido" que
/// "surco". Esos tres valores se toman tal cual.
///
/// Lo que NO se toma tal cual es la fusion del glifo con el fondo. El usuario
/// la calibro en 0.50 mirando modo oscuro, donde queda al borde (4.30:1), pero
/// la paleta clara tiene mucho menos margen de luminancia y ahi la misma fusion
/// cae a 2.83:1. Por eso la fusion es por MODO y por NIVEL, con los techos
/// medidos:
///
/// | | fusion max 4.5:1 | fusion max 3:1 |
/// |---|---|---|
/// | oscuro | 0.48 | 0.62 |
/// | claro | 0.32 | 0.47 |
///
/// El tallado se consigue acercando el glifo al color de su superficie, asi que
/// es literalmente contraste gastado en estetica. Gastarlo donde el tamano lo
/// compensa (numeros grandes, iconos) y no donde hay que leer.
enum TalladoNivel {
  /// Texto de lectura. Se queda por debajo del techo de 4.5:1 (AA normal).
  sutil,

  /// Texto de 24px o mas e iconos, donde WCAG permite 3:1 — texto grande por
  /// 1.4.3, elementos no textuales por 1.4.11. Aca el tallado se ve de verdad.
  marcado,
}

/// Desplazamiento en px de las capas de luz y sombra.
const double bentoTalladoProfundidad = 1.25;

const double _luzIntensidad = 0.70;
const double _sombraIntensidad = 0.65;

const _fusion = {
  TalladoNivel.sutil: (claro: 0.28, oscuro: 0.42),
  TalladoNivel.marcado: (claro: 0.46, oscuro: 0.62),
};

/// Color de glifo tallado: el color base acercado a su superficie.
///
/// [sobre] es la superficie donde cae el glifo — el pozo o la bandeja. Pasarla
/// mal es el bug que ya aparecio dos veces en este proyecto, asi que es
/// obligatoria y no tiene default.
Color bentoColorTallado(
  BuildContext context, {
  required Color base,
  required Color sobre,
  TalladoNivel nivel = TalladoNivel.sutil,
}) {
  final claro = Theme.of(context).brightness == Brightness.light;
  final f = _fusion[nivel]!;
  return Color.lerp(base, sobre, claro ? f.claro : f.oscuro)!;
}

/// Aplica el relieve a cualquier hijo — texto, icono de Material o SVG propio.
///
/// `ColorFiltered` con `srcATop` respeta el alfa del hijo, asi que no hace
/// falta una implementacion por tipo de widget.
class BentoTallado extends StatelessWidget {
  const BentoTallado({
    super.key,
    required this.child,
    required this.sobre,
    this.profundidad = bentoTalladoProfundidad,
  });

  final Widget child;

  /// La superficie donde cae el glifo: de ella se derivan la luz y la sombra
  /// de la incision, para que el relieve funcione igual sobre pozo o bandeja.
  final Color sobre;

  final double profundidad;

  @override
  Widget build(BuildContext context) {
    if (profundidad <= 0) return child;

    // La pared de arriba de la incision queda en sombra y su fondo atrapa luz
    // desde arriba: sombra desplazada hacia arriba, luz hacia abajo.
    final luz = Color.lerp(sobre, Colors.white, _luzIntensidad)!;
    final sombra = Color.lerp(sobre, Colors.black, _sombraIntensidad)!;

    Widget capa(Color color, double dy) {
      return Transform.translate(
        offset: Offset(0, dy),
        child: ColorFiltered(colorFilter: ColorFilter.mode(color, BlendMode.srcATop), child: child),
      );
    }

    return Stack(children: [capa(sombra, -profundidad), capa(luz, profundidad), child]);
  }
}

/// Texto tallado. Atajo para el caso mas comun: resuelve el color del glifo y
/// le aplica el relieve en un solo paso.
class BentoTextoTallado extends StatelessWidget {
  const BentoTextoTallado(
    this.texto, {
    super.key,
    required this.sobre,
    this.estilo,
    this.nivel = TalladoNivel.sutil,
    this.maxLines,
    this.overflow,
  });

  final String texto;
  final Color sobre;
  final TextStyle? estilo;
  final TalladoNivel nivel;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final base = estilo?.color ?? DefaultTextStyle.of(context).style.color!;
    return BentoTallado(
      sobre: sobre,
      child: Text(
        texto,
        maxLines: maxLines,
        overflow: overflow,
        style: (estilo ?? const TextStyle()).copyWith(
          color: bentoColorTallado(context, base: base, sobre: sobre, nivel: nivel),
        ),
      ),
    );
  }
}
