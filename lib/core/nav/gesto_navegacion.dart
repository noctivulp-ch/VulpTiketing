import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Deslizar de lado para cambiar de ventana.
///
/// **Un dedo navega; dos o tres hacen cosas.** Esa es la convención de gestos de
/// la app, y este widget sostiene su mitad: reconoce el arrastre horizontal
/// solo mientras haya **un** puntero en pantalla, y se aparta en cuanto aparece
/// un segundo. Así los gestos de dos y tres dedos quedan libres para acciones,
/// sin tener que renegociar nada cuando se agreguen.
///
/// Deslizar a la **izquierda** lleva a la ventana siguiente, como pasar la hoja
/// de un cuaderno. En los extremos no da la vuelta: saltar de Configuración a
/// Venta Rápida de un tirón desorienta más de lo que ahorra.
class NavegacionPorGesto extends StatefulWidget {
  const NavegacionPorGesto({
    super.key,
    required this.indice,
    required this.cantidad,
    required this.onCambio,
    required this.child,
  });

  final int indice;
  final int cantidad;
  final ValueChanged<int> onCambio;
  final Widget child;

  /// Cuánto hay que arrastrar para que cuente, si se suelta despacio. Es una
  /// fracción del ancho y no un número de píxeles: en un teléfono acostado la
  /// pantalla mide el doble, y pedir el mismo recorrido haría el gesto el doble
  /// de trabajoso.
  static const _fraccionMinima = 0.18;

  /// A partir de esta velocidad no hace falta recorrido: es el gesto rápido de
  /// "pasar la hoja", que en un teléfono se hace con el pulgar sin estirar.
  static const _velocidadMinima = 320.0;

  @override
  State<NavegacionPorGesto> createState() => _NavegacionPorGestoState();
}

class _NavegacionPorGestoState extends State<NavegacionPorGesto> {
  /// Punteros que hay ahora mismo en la pantalla.
  ///
  /// Se cuentan a mano porque un `HorizontalDragGestureRecognizer` normal sigue
  /// atendiendo al primer dedo aunque aparezca un segundo: con dos dedos
  /// deslizando, cambiaría de ventana igual. Y eso es justo lo que hay que
  /// dejar libre.
  int _punteros = 0;

  double _recorrido = 0;
  bool _cancelado = false;

  void _empezar(DragStartDetails _) {
    _recorrido = 0;
    _cancelado = _punteros > 1;
  }

  void _mover(DragUpdateDetails detalles) {
    // Un segundo dedo a mitad del arrastre lo anula: el gesto pasó a ser otra
    // cosa, y terminarlo como navegación sería adivinar.
    if (_punteros > 1) _cancelado = true;
    _recorrido += detalles.delta.dx;
  }

  void _terminar(DragEndDetails detalles) {
    if (_cancelado) return;

    final ancho = context.size?.width ?? MediaQuery.sizeOf(context).width;
    final velocidad = detalles.velocity.pixelsPerSecond.dx;
    final suficiente =
        _recorrido.abs() > ancho * NavegacionPorGesto._fraccionMinima ||
        velocidad.abs() > NavegacionPorGesto._velocidadMinima;
    if (!suficiente) return;

    // El signo del RECORRIDO manda, no el de la velocidad: al soltar se puede
    // frenar hacia atrás y la velocidad final apuntar al revés de lo que se
    // arrastró.
    final destino = widget.indice + (_recorrido < 0 ? 1 : -1);
    if (destino < 0 || destino >= widget.cantidad) return;
    widget.onCambio(destino);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // `Listener` y no `GestureDetector` para contar: los punteros llegan acá
      // antes de que ningún reconocedor los reclame.
      onPointerDown: (_) => _punteros++,
      onPointerUp: (_) => _punteros = _punteros > 0 ? _punteros - 1 : 0,
      onPointerCancel: (_) => _punteros = _punteros > 0 ? _punteros - 1 : 0,
      child: RawGestureDetector(
        // `deferToChild`: lo que ya escucha un toque —un botón, una lista— lo
        // sigue recibiendo. Este gesto solo entra donde nadie lo reclama.
        behavior: HitTestBehavior.deferToChild,
        gestures: {
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
                HorizontalDragGestureRecognizer.new,
                (instancia) => instancia
                  ..onStart = _empezar
                  ..onUpdate = _mover
                  ..onEnd = _terminar,
              ),
        },
        child: widget.child,
      ),
    );
  }
}
