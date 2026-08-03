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
    this.alDeslizarIzquierda,
    this.alDeslizarDerecha,
    required this.child,
  });

  /// Qué hacer al arrastrar hacia abajo con dos dedos.
  final VoidCallback? alDeslizarAbajo;

  /// Y hacia arriba.
  final VoidCallback? alDeslizarArriba;

  /// Horizontal, para lo que se recorre de lado: en Reportes, el rango.
  ///
  /// Con un dedo el horizontal ya es cambiar de ventana, así que estos dos solo
  /// existen con dos dedos — la convención se sostiene sola.
  final VoidCallback? alDeslizarIzquierda;
  final VoidCallback? alDeslizarDerecha;

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
  Offset _recorrido = Offset.zero;
  bool _disparado = false;

  void _empezar(ScaleStartDetails detalles) {
    _recorrido = Offset.zero;
    _disparado = false;
  }

  void _mover(ScaleUpdateDetails detalles) {
    // Con uno o con tres, esto no es. Se reinicia el acumulado para que un dedo
    // que se levanta a mitad no deje medio gesto cargado.
    if (detalles.pointerCount != 2) {
      _recorrido = Offset.zero;
      return;
    }
    if (_disparado) return;

    _recorrido += detalles.focalPointDelta;

    // El eje DOMINANTE decide. Nadie arrastra dos dedos perfectamente rectos, y
    // sin esto un gesto lateral con algo de caída dispararía las dos cosas —o
    // la que no era.
    final vertical = _recorrido.dy.abs() >= _recorrido.dx.abs();
    final avance = vertical ? _recorrido.dy : _recorrido.dx;
    if (avance.abs() < GestoDeDosDedos.umbral) return;

    final accion = vertical
        ? (avance > 0 ? widget.alDeslizarAbajo : widget.alDeslizarArriba)
        : (avance > 0 ? widget.alDeslizarDerecha : widget.alDeslizarIzquierda);
    if (accion == null) return;

    // Una vez por gesto: sin esto, seguir arrastrando dispararía en cada frame.
    _disparado = true;
    accion();
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
