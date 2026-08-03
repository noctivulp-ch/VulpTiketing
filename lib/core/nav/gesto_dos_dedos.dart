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
///
/// Escucha con un `Listener`, **fuera de la arena de gestos**. Es lo que hace
/// que funcione encima de una lista: con un reconocedor, el `ListView` del
/// detalle de Reportes ganaba la disputa y el gesto no llegaba nunca —
/// comprobado en el aparato, andaba sobre el total y no sobre las ventas, que
/// es justo donde cae el dedo—. Un `Listener` no compite: ve los punteros pase
/// lo que pase.
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
  /// Dónde está cada dedo ahora mismo.
  final _dedos = <int, Offset>{};

  /// Cuánto se movió el punto medio entre los dos dedos desde que se apoyaron.
  Offset _recorrido = Offset.zero;
  bool _disparado = false;

  void _apoyar(PointerDownEvent evento) {
    _dedos[evento.pointer] = evento.position;
    // El gesto empieza cuando se apoya el SEGUNDO: hasta ahí no hay nada que
    // acumular, y arrancar con el primero cargaría el recorrido del dedo que
    // navega.
    if (_dedos.length == 2) {
      _recorrido = Offset.zero;
      _disparado = false;
    }
  }

  void _mover(PointerMoveEvent evento) {
    final anterior = _dedos[evento.pointer];
    _dedos[evento.pointer] = evento.position;
    if (anterior == null || _dedos.length != 2 || _disparado) return;

    // El punto medio se mueve la mitad de lo que se mueve un dedo, así que el
    // recorrido del foco es la suma de los deltas partida por dos.
    _recorrido += (evento.position - anterior) / 2;

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

  void _levantar(PointerEvent evento) {
    _dedos.remove(evento.pointer);
    if (_dedos.isEmpty) _recorrido = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _apoyar,
      onPointerMove: _mover,
      onPointerUp: _levantar,
      onPointerCancel: _levantar,
      // `translucent`: se mete SIEMPRE en el camino del toque, y aun así deja
      // pasar todo a lo que hay debajo. Con `deferToChild` el gesto funcionaba
      // sobre el total pero no sobre la lista de ventas —o sea, justo donde cae
      // el dedo—, porque ahí el `ListView` resolvía el hit-test y este widget
      // se quedaba fuera del reparto.
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
