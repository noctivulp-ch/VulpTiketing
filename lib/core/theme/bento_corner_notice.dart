import 'package:flutter/material.dart';

import 'bento_theme.dart';

/// Notificacion de esquina, no intrusiva, se auto-oculta — ver
/// docs/pantallas/prototipos-ascii.md#feedback-de-finalizacion-universal-no-solo-venta.
/// Reemplaza `ScaffoldMessenger.showSnackBar` (que ocupa el ancho de la
/// pantalla y bloquea la barra inferior) para cualquier accion de
/// completitud: venta finalizada, producto creado/editado/descontinuado/
/// purgado, backup exportado/restaurado, catalogo importado, etc. — mismo
/// patron siempre, en toda la app.
void mostrarNotificacionEsquina(BuildContext context, String mensaje) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entrada;
  entrada = OverlayEntry(
    builder: (context) => _NotificacionEsquina(mensaje: mensaje, onTerminar: () => entrada.remove()),
  );
  overlay.insert(entrada);
}

class _NotificacionEsquina extends StatefulWidget {
  const _NotificacionEsquina({required this.mensaje, required this.onTerminar});

  final String mensaje;
  final VoidCallback onTerminar;

  @override
  State<_NotificacionEsquina> createState() => _NotificacionEsquinaState();
}

class _NotificacionEsquinaState extends State<_NotificacionEsquina>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controlador;
  late final Animation<double> _opacidad;

  static const _duracionVisible = Duration(milliseconds: 1500);
  static const _duracionFade = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _controlador = AnimationController(duration: _duracionFade, vsync: this);
    _opacidad = CurvedAnimation(parent: _controlador, curve: Curves.easeOut);
    _controlador.forward();
    Future.delayed(_duracionVisible, () async {
      if (!mounted) return;
      await _controlador.reverse();
      widget.onTerminar();
    });
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: BentoSpacing.gapGrupo,
      bottom: BentoSpacing.gapGrupo,
      child: SafeArea(
        child: FadeTransition(
          opacity: _opacidad,
          child: Material(
            color: Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(BentoRadius.celda),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BentoSpacing.paddingCelda,
                vertical: BentoSpacing.unidad,
              ),
              child: Text(
                widget.mensaje,
                style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
