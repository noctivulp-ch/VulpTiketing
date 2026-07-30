import 'package:flutter/material.dart';

/// El gesto/botón de retroceso de Android cierra el nivel abierto en vez de
/// salir de la app.
///
/// La app no navega con rutas: cada pantalla abre sus sub-niveles con estado
/// local (`_panelAbierto`, `_turnoSeleccionado`, `_seleccion`…). Para el sistema
/// operativo eso es UNA sola pantalla, así que el retroceso salía directo de la
/// app aunque el usuario estuviera dos niveles adentro — que es la forma más
/// rápida de perder un carrito a medio armar.
///
/// Los diálogos (`showDialog`) NO necesitan esto: van al Navigator y el
/// retroceso ya los cierra solo. Esto es para los niveles que viven en estado.
///
/// Uso: envolver el cuerpo de la pantalla y decir cuándo hay algo que cerrar.
///
/// ```dart
/// RetrocesoCierra(
///   activo: _panelAbierto,
///   alRetroceder: () => setState(() => _panelAbierto = false),
///   child: …,
/// )
/// ```
class RetrocesoCierra extends StatelessWidget {
  const RetrocesoCierra({
    super.key,
    required this.activo,
    required this.alRetroceder,
    required this.child,
  });

  /// Si hay un nivel abierto que el retroceso deba cerrar. En falso, el
  /// retroceso hace lo de siempre (salir de la app).
  final bool activo;

  final VoidCallback alRetroceder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // `canPop: !activo` es lo que decide: con un nivel abierto el sistema NO
      // saca la pantalla, y nos llega el aviso para cerrarlo a mano.
      canPop: !activo,
      onPopInvokedWithResult: (salio, _) {
        if (salio) return;
        alRetroceder();
      },
      child: child,
    );
  }
}
