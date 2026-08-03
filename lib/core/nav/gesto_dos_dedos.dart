import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Un arrastre vertical de **dos dedos**, para acciones.
///
/// La otra mitad de la convención de gestos (decisión 0030): un dedo navega,
/// dos o tres hacen cosas. Este widget solo reacciona con **exactamente dos**
/// punteros — con uno se aparta, para que la navegación por deslizamiento y los
/// scrolls sigan funcionando igual.
///
/// Dispara **al cruzar el umbral**, no al soltar. La app prioriza velocidad:
/// esperar a que se levanten los dedos agrega una espera que no aporta nada, y
/// el gesto se siente muerto mientras tanto.
class GestoDeDosDedos extends StatefulWidget {
  const GestoDeDosDedos({
    super.key,
    this.alDeslizarAbajo,
    this.alDeslizarArriba,
    required this.child,
  });

  /// Qué hacer al arrastrar hacia abajo con dos dedos.
  final VoidCallback? alDeslizarAbajo;

  /// Y hacia arriba.
  final VoidCallback? alDeslizarArriba;

  final Widget child;

  /// Cuánto hay que recorrer para que cuente.
  ///
  /// Un objetivo táctil (48 dp): lo bastante como para que no salte al apoyar
  /// dos dedos y ajustar el agarre, y lo bastante poco como para hacerse con el
  /// pulgar y el índice sin recolocar la mano.
  static const umbral = 48.0;

  @override
  State<GestoDeDosDedos> createState() => _GestoDeDosDedosState();
}

class _GestoDeDosDedosState extends State<GestoDeDosDedos> {
  double _recorrido = 0;
  bool _disparado = false;

  void _empezar(ScaleStartDetails detalles) {
    _recorrido = 0;
    _disparado = false;
  }

  void _mover(ScaleUpdateDetails detalles) {
    // Con uno o con tres, esto no es. Se reinicia el acumulado para que un dedo
    // que se levanta a mitad no deje medio gesto cargado.
    if (detalles.pointerCount != 2) {
      _recorrido = 0;
      return;
    }
    if (_disparado) return;

    _recorrido += detalles.focalPointDelta.dy;
    if (_recorrido.abs() < GestoDeDosDedos.umbral) return;

    // Una vez por gesto: sin esto, seguir arrastrando dispararía en cada frame.
    _disparado = true;
    if (_recorrido > 0) {
      widget.alDeslizarAbajo?.call();
    } else {
      widget.alDeslizarArriba?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      // `ScaleGestureRecognizer` y no un drag: es el único de la casa que sabe
      // cuántos dedos hay (`pointerCount`). Un `VerticalDragGestureRecognizer`
      // sigue al primer puntero y no distingue uno de dos, que es justo la
      // distinción sobre la que se apoya toda la convención.
      gestures: {
        ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
          ScaleGestureRecognizer.new,
          (instancia) => instancia
            ..onStart = _empezar
            ..onUpdate = _mover,
        ),
      },
      // `deferToChild`: lo que ya escucha un toque lo sigue recibiendo.
      behavior: HitTestBehavior.deferToChild,
      child: widget.child,
    );
  }
}
