import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Los atajos de teclado de escritorio.
///
/// Existen por **paridad**: en el teléfono, cambiar de ventana, abrir el panel
/// de productos o exportar un reporte son gestos. En escritorio no hay dedos, y
/// hasta acá todo eso solo se podía hacer con el ratón — incluido exportar, que
/// vivía escondido en un "mantener presionado". Quien trabaja con teclado hacía
/// el doble de camino para lo mismo.
///
/// La regla de qué lleva `Ctrl` y qué no: **con `Ctrl` lo que podría chocar con
/// escribir** (letras, números, flechas donde hay campos de texto); **sin
/// `Ctrl` lo que no** — Reportes no tiene un solo campo, así que ahí las flechas
/// son directas.
///
/// Se envuelve con [CallbackShortcuts] y no con `Shortcuts`/`Actions` porque
/// estas acciones no viajan por el árbol: cada pantalla declara las suyas donde
/// las usa, y las que no coinciden siguen subiendo solas.
class AtajosDeVentana extends StatelessWidget {
  const AtajosDeVentana({
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

  void _mover(int paso) {
    final destino = indice + paso;
    // En los extremos no da la vuelta, igual que el gesto.
    if (destino < 0 || destino >= cantidad) return;
    onCambio(destino);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Ctrl+1..5 va DIRECTO a una ventana. Es lo más rápido cuando ya se
        // sabe a dónde se va, que es casi siempre.
        for (var i = 0; i < cantidad && i < 9; i++)
          SingleActivator(_digitos[i], control: true): () => onCambio(i),
        const SingleActivator(LogicalKeyboardKey.tab, control: true): () => _mover(1),
        const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () =>
            _mover(-1),
        // Las flechas con Ctrl, porque sin él son de los campos y las listas.
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () => _mover(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () => _mover(-1),
      },
      // `Focus` con `autofocus`: sin foco no llega ni una tecla, y el shell no
      // tiene ningún campo que lo tome por su cuenta al arrancar.
      child: Focus(autofocus: true, child: child),
    );
  }

  static const _digitos = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
}
