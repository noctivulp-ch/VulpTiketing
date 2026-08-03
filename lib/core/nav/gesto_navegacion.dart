import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Deslizar de lado para cambiar de ventana.
///
/// **Un dedo navega; dos o tres hacen cosas.** Esa es la convención de gestos de
/// la app, y este widget sostiene su mitad: reconoce el arrastre horizontal
/// solo mientras haya **un** puntero en pantalla, y **se retira de la arena** en
/// cuanto aparece un segundo.
///
/// Retirarse es la palabra importante. Ignorar el gesto no alcanza: este widget
/// envuelve la app entera, así que si su reconocedor se queda en la arena, gana
/// —está más arriba y acepta antes— y la acción de dos dedos de la pantalla
/// nunca llega a reclamarla. Fue exactamente lo que pasó: el gesto lateral de
/// dos dedos de Reportes no hacía nada en el aparato, y cada widget pasaba su
/// propia prueba por separado.
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
  double _recorrido = 0;
  _ArrastreDeUnDedo? _reconocedor;

  void _empezar(DragStartDetails _) {
    _recorrido = 0;
  }

  void _mover(DragUpdateDetails detalles) {
    _recorrido += detalles.delta.dx;
  }

  void _terminar(DragEndDetails detalles) {
    // Retirarse de la arena no alcanza cuando el primer dedo YA había ganado —
    // que es lo que pasa cuando nadie compite—: ahí `resolve` no deshace nada y
    // el arrastre sigue vivo. Por eso el reconocedor además se marca, y acá no
    // se navega.
    if (_reconocedor?.invalidado ?? false) return;

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
    return RawGestureDetector(
      // `deferToChild`: lo que ya escucha un toque —un botón, una lista— lo
      // sigue recibiendo. Este gesto solo entra donde nadie lo reclama.
      behavior: HitTestBehavior.deferToChild,
      gestures: {
        _ArrastreDeUnDedo: GestureRecognizerFactoryWithHandlers<_ArrastreDeUnDedo>(
          _ArrastreDeUnDedo.new,
          (instancia) => _reconocedor = instancia
            ..onStart = _empezar
            ..onUpdate = _mover
            ..onEnd = _terminar,
        ),
      },
      child: widget.child,
    );
  }
}

/// Un arrastre horizontal que **se retira** en cuanto hay un segundo dedo.
///
/// `HorizontalDragGestureRecognizer` sigue atendiendo al primer puntero aunque
/// aparezcan más: con dos dedos deslizando cambiaría de ventana igual, y —peor—
/// se quedaría con la victoria en la arena, dejando sin gesto a la acción de dos
/// dedos de la pantalla.
///
/// `resolve(rejected)` es lo que lo suelta: retira a este reconocedor de la
/// disputa y deja que la gane quien sí sabe qué hacer con dos dedos.
class _ArrastreDeUnDedo extends HorizontalDragGestureRecognizer {
  int _punteros = 0;

  /// Hubo un segundo dedo en este gesto, así que ya no es navegación.
  ///
  /// Hace falta además del `resolve` porque retirarse de la arena solo sirve
  /// mientras la disputa siga abierta: si este reconocedor ya la había ganado
  /// —no había con quién competir—, el arrastre continúa igual.
  bool invalidado = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _punteros++;
    // El primer dedo abre un gesto nuevo y limpio. Se reinicia acá y no al
    // dejar de rastrear: `resolve(rejected)` deja de rastrear en el acto, así
    // que resetear ahí borraba la marca ANTES de que el arrastre terminara — y
    // el gesto de dos dedos volvía a navegar.
    if (_punteros == 1) invalidado = false;
    if (_punteros > 1) {
      invalidado = true;
      resolve(GestureDisposition.rejected);
      return;
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    // Sin esto, un puntero que no se aceptó dejaría el contador desbalanceado.
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _punteros = 0;
    super.didStopTrackingLastPointer(pointer);
  }
}
