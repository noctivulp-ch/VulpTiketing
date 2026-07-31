import 'package:flutter/material.dart';

/// Efectos visuales que se pueden apagar desde Configuración → Optimización.
///
/// Acá va lo que **cuesta pintar y no cambia lo que la app hace**: adorno, no
/// función. El aparato del negocio es de gama baja, y en él la diferencia entre
/// un desplazamiento fluido y uno con tirones puede ser un solo efecto.
///
/// Para agregar uno nuevo: una constante acá, respetarla donde se pinta, y una
/// entrada en el panel de Optimización. Nada más — el resto lo lleva el tema.
enum EfectoPesado {
  /// El relieve grabado de los números y los iconos: pinta el mismo glifo tres
  /// veces (sombra, luz y glifo) para que se lea hundido en la superficie.
  ///
  /// Medido en el teléfono del negocio: apagarlo baja el raster al desplazar el
  /// catálogo de 12,9 ms a 7,9 y los frames fuera de presupuesto de 50 a 4.
  /// Es, por lejos, el efecto más caro de la app —
  /// ver docs/arquitectura/rendimiento.md.
  tallado;

  String get etiqueta => switch (this) {
    EfectoPesado.tallado => 'Relieve grabado',
  };

  String get explicacion => switch (this) {
    EfectoPesado.tallado =>
      'Los números y los iconos se ven hundidos en la superficie. Apagarlo es lo '
          'que más alivia el desplazamiento en teléfonos lentos.',
  };
}

/// Qué efectos están apagados, disponible en cualquier punto del árbol.
///
/// Va por el TEMA y no por Riverpod a propósito: los widgets de `core/theme/`
/// no conocen las features, y así `BentoTallado` no necesita saber que existe
/// una pantalla de Configuración. `lib/app.dart` traduce la preferencia a esto.
@immutable
class BentoEfectos extends ThemeExtension<BentoEfectos> {
  const BentoEfectos({this.apagados = const {}});

  final Set<EfectoPesado> apagados;

  bool activo(EfectoPesado efecto) => !apagados.contains(efecto);

  @override
  BentoEfectos copyWith({Set<EfectoPesado>? apagados}) =>
      BentoEfectos(apagados: apagados ?? this.apagados);

  /// Sin interpolación: un efecto está o no está, y medio efecto durante la
  /// transición de tema se vería como un parpadeo.
  @override
  BentoEfectos lerp(ThemeExtension<BentoEfectos>? other, double t) =>
      t < 0.5 ? this : (other as BentoEfectos? ?? this);
}

/// Si un efecto debe pintarse en este punto del árbol.
///
/// Devuelve `true` cuando no hay tema con la extensión —tests de widget
/// sueltos, por ejemplo—: el comportamiento por defecto es la app completa.
bool bentoEfectoActivo(BuildContext context, EfectoPesado efecto) =>
    Theme.of(context).extension<BentoEfectos>()?.activo(efecto) ?? true;
