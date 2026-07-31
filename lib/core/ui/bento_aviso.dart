import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/bento_theme.dart';
import '../theme/bento_velo.dart';

/// El aviso de la app. **Uno solo, para todo**: venta finalizada, producto
/// guardado o descontinuado, backup exportado, reporte guardado, y también lo
/// que salió mal cuando no amerita ocupar la pantalla.
///
/// Sustituye a `ScaffoldMessenger.showSnackBar`, que ocupa el ancho completo y
/// tapa la barra inferior — justo donde están el buscador y los botones de
/// cobro.
///
/// Reglas de la pieza:
/// - **Un rectángulo**, con el fondo del tema y la cresta del material elegido
///   por borde. Es la misma cresta que marca un pozo seleccionado: el aviso se
///   lee como una pieza de la app, no como un cartel del sistema.
/// - **Entra y sale empujando desde la derecha**, no con un fundido: el
///   movimiento dice de dónde viene y a dónde se va, y hacia el lado corto —
///   entrar desde arriba lo cruzaría por delante del contenido que se está
///   mirando.
/// - **Dos segundos**, y se va solo. Un toque lo saca antes.
/// - **Se adapta al texto**, con un tope de media pantalla: pasado eso baja de
///   línea en vez de estirarse. Una tira larguísima de una sola línea no se
///   lee de un vistazo, que es lo único que un aviso tiene que conseguir.
void mostrarAviso(BuildContext context, String mensaje) {
  final overlay = Overlay.of(context);

  // Uno a la vez: dos avisos encimados se tapan entre sí y ninguno se lee. El
  // nuevo reemplaza al anterior, que es lo que pasa cuando alguien encadena
  // acciones rápido.
  _activo?.remove();

  late final OverlayEntry entrada;
  entrada = OverlayEntry(
    builder: (context) => _Aviso(
      mensaje: mensaje,
      onTerminar: () {
        if (_activo == entrada) _activo = null;
        entrada.remove();
      },
    ),
  );
  _activo = entrada;
  overlay.insert(entrada);
}

OverlayEntry? _activo;

class _Aviso extends StatefulWidget {
  const _Aviso({required this.mensaje, required this.onTerminar});

  final String mensaje;
  final VoidCallback onTerminar;

  @override
  State<_Aviso> createState() => _AvisoState();
}

class _AvisoState extends State<_Aviso> with SingleTickerProviderStateMixin {
  static const _visible = Duration(seconds: 2);
  static const _entrada = Duration(milliseconds: 220);

  /// Al tocarlo se va MÁS RÁPIDO de lo que entró: tocar un aviso es decir "ya
  /// lo vi", y hacerlo esperar la misma animación se siente pegajoso.
  static const _salidaPorToque = Duration(milliseconds: 120);

  late final AnimationController _controlador = AnimationController(
    duration: _entrada,
    reverseDuration: _entrada,
    vsync: this,
  );
  late final Animation<Offset> _empuje = _controlador.drive(
    Tween(
      begin: const Offset(1.4, 0),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic)),
  );

  bool _cerrando = false;

  /// Guardado para poder cancelarlo: al sacar el aviso con un toque, un
  /// `Future.delayed` suelto seguía vivo hasta cumplir sus dos segundos contra
  /// un widget ya desmontado.
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _controlador.forward();
    _reloj = Timer(_visible, () => _cerrar(_entrada));
  }

  Future<void> _cerrar(Duration duracion) async {
    if (_cerrando || !mounted) return;
    _cerrando = true;
    _reloj?.cancel();
    _controlador.reverseDuration = duracion;
    await _controlador.reverse();
    if (mounted) widget.onTerminar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final acento = Theme.of(context).colorScheme.primary;

    return Positioned(
      left: BentoSpacing.gapGrupo,
      right: BentoSpacing.gapGrupo,
      // Arriba a la derecha, y por debajo de la zona reservada del borde
      // superior: ahí es donde caen la muesca de la cámara y las
      // notificaciones del sistema.
      top: bentoInsetSuperior(context),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: SlideTransition(
            position: _empuje,
            child: ConstrainedBox(
              // Media pantalla de tope. Más largo que eso deja de ser algo que
              // se capta de un vistazo, así que baja de línea.
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width / 2),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => _cerrar(_salidaPorToque),
                  borderRadius: BorderRadius.circular(BentoRadius.pozo),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: laca.pozo,
                      borderRadius: BorderRadius.circular(BentoRadius.pozo),
                      // La cresta del material elegido: el mismo borde que
                      // marca un pozo seleccionado. Sin sombra — la profundidad
                      // de esta app la carga la cresta (DESIGN.md, regla 1).
                      border: Border.all(color: acento),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BentoSpacing.paddingCelda,
                        vertical: BentoSpacing.unidad,
                      ),
                      child: Text(
                        widget.mensaje,
                        // Sin `maxLines`: el aviso crece las líneas que haga
                        // falta, que es lo que permite que el texto entre
                        // entero.
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
