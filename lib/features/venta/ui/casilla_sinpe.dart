import 'package:flutter/material.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';

/// La casilla de SINPE, igual en las dos pantallas de venta.
///
/// Una **casilla** y no un selector de dos opciones: en la soda se cobra en
/// efectivo casi siempre, así que pedir que se elija en cada venta lo que nueve
/// de cada diez veces es lo mismo agrega un toque por venta a cambio de nada.
/// Efectivo es lo que pasa si nadie hace nada.
///
/// Un pozo y no un `Checkbox`: es lo mismo que usa el resto de la app para "esto
/// está elegido", y un control de Material acá se leería como una pieza pegada
/// encima de la bandeja (DESIGN.md, regla 8). El cuadro de la izquierda es lo
/// que la hace reconocible como casilla.
class CasillaSinpe extends StatelessWidget {
  const CasillaSinpe({super.key, required this.activa, required this.onCambio});

  final bool activa;
  final ValueChanged<bool> onCambio;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final acento = Theme.of(context).colorScheme.primary;

    return SizedBox(
      // El objetivo táctil completo (regla 7): se toca con el pulgar mientras se
      // cobra, no con el dedo apuntando.
      height: bentoObjetivoTactilMin,
      child: BentoPozo(
        onTap: () => onCambio(!activa),
        seleccionado: activa,
        padding: const EdgeInsets.symmetric(horizontal: BentoSpacing.unidad),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              activa ? Icons.check_box_outlined : Icons.check_box_outline_blank,
              size: 20,
              color: activa ? acento : laca.textoAtenuadoEnBandeja,
            ),
            const SizedBox(width: BentoSpacing.unidad / 2),
            // Se encoge en vez de partirse: en la celda más angosta de la barra
            // de cobro "SINPE" tiene que seguir siendo una línea.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'SINPE',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: activa ? acento : laca.textoEnBandeja,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
