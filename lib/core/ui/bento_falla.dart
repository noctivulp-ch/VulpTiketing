import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/bento_bandeja.dart';
import '../theme/bento_theme.dart';

/// Qué se muestra cuando algo no se pudo cargar.
///
/// Nace de un caso real: Reportes falló en un teléfono y lo que apareció fue un
/// `DatabaseException` con el SQL completo, a pantalla llena, delante de quien
/// atiende la soda. El error estaba capturado —el `FutureProvider` tiene su
/// rama `error:`— pero capturar no es lo mismo que **contar**.
///
/// Dos audiencias distintas, y por eso dos niveles:
/// - quien usa la app lee una frase en su idioma y un botón para reintentar;
/// - quien la desarrolla ve el detalle técnico, pero **solo en depuración**
///   ([kDebugMode]), porque en el mostrador no le sirve a nadie y encima puede
///   filtrar nombres de tablas y consultas.
///
/// Lo que NO hace: tragarse el error. El fallo se sigue viendo, y sigue siendo
/// evidente que algo está mal — un cero silencioso habría dejado a la soda
/// creyendo que no vendió nada.
class BentoFalla extends StatelessWidget {
  const BentoFalla({
    super.key,
    required this.mensaje,
    this.error,
    this.onReintentar,
    bool? mostrarDetalle,
  }) : mostrarDetalle = mostrarDetalle ?? kDebugMode;

  /// Qué pasó, en el idioma de quien atiende. "No se pudieron cargar las
  /// ventas", no "DatabaseException".
  final String mensaje;

  /// El error real. Solo se muestra si [mostrarDetalle].
  final Object? error;

  final VoidCallback? onReintentar;

  /// Parametrizable para poder probar las dos caras; por defecto sigue a
  /// [kDebugMode].
  final bool mostrarDetalle;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BentoSpacing.pared),
        child: BentoPozo(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(mensaje, style: textos.titleSmall),
              if (onReintentar != null) ...[
                const SizedBox(height: BentoSpacing.unidad),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: onReintentar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ),
              ],
              if (mostrarDetalle && error != null) ...[
                const SizedBox(height: BentoSpacing.unidad),
                // Plegado: el detalle es para depurar, no para mirar de frente.
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text('Detalle técnico', style: textos.bodySmall),
                  children: [SelectableText('$error', style: textos.bodySmall)],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
