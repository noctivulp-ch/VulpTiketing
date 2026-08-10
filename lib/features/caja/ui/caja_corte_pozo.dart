import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../caja_notifier.dart';
import '../corte_caja_model.dart';
import 'corte_caja_dialog.dart';

/// El cuadro de corte de caja: lo que hay que contar y con qué compararlo.
///
/// Va debajo del total del día y no lo sustituye. Son dos preguntas distintas:
/// el total dice **cuánto vendió la tienda** —efectivo y SINPE juntos— y esto
/// dice **cuánto debería haber dentro del cajón**, que es solo efectivo. Se
/// parecen y no son lo mismo: confundirlos es cuadrar la caja contra un número
/// que incluye transferencias que nunca entraron en ella.
class CajaCortePozo extends ConsumerWidget {
  const CajaCortePozo({super.key, required this.editable});

  /// Los cortes se anotan sobre el día de hoy. Mirando un día pasado el cuadro
  /// se ve pero no se toca: anotar el conteo de ayer no tiene sentido, y dejar
  /// el gesto disponible invita a hacerlo por costumbre.
  final bool editable;

  Future<void> _editar(BuildContext context, WidgetRef ref, EstadoCaja estado) async {
    final siguiente = estado.siguiente;
    if (siguiente == null) {
      mostrarAviso(context, 'La caja de hoy ya se cerró');
      return;
    }

    final resultado = await mostrarDialogoDeCorte(context, siguiente: siguiente);
    if (resultado == null || !context.mounted) return;

    final ok = await ref
        .read(cajaNotifierProvider.notifier)
        .registrar(resultado.momento, resultado.monto);
    if (!context.mounted) return;
    mostrarAviso(
      context,
      ok
          ? '✓ ${nombreDeMomento(resultado.momento)} anotado'
          : '✗ Ese corte ya no era el que tocaba',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(cajaNotifierProvider).valueOrNull ?? const EstadoCaja.vacia();
    final textos = Theme.of(context).textTheme;

    return BentoPozo(
      onTap: editable ? () => _editar(context, ref, estado) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: BentoSpacing.paddingCelda,
        vertical: BentoSpacing.unidad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _linea(context, 'Caja Inicial', estado.cajaInicial),
          const SizedBox(height: BentoSpacing.unidad),
          _linea(context, 'Caja Total', estado.cajaTotal),
          if (estado.siguiente != null && editable) ...[
            const SizedBox(height: BentoSpacing.unidad / 2),
            // Qué corte toca, dicho en el propio cuadro: sin esto hay que abrir
            // el diálogo para averiguar en qué punto del día va la caja.
            Text(
              'Toca: ${nombreDeMomento(estado.siguiente!)}',
              style: textos.bodySmall,
              maxLines: 1,
            ),
          ],
        ],
      ),
    );
  }

  Widget _linea(BuildContext context, String titulo, double monto) {
    final textos = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Una línea cada uno y encogiendo si hace falta: en la columna angosta
        // del modo acostado, "Caja Inicial" se partía en dos renglones.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(titulo, style: textos.bodyMedium, maxLines: 1),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('₡${monto.toStringAsFixed(2)}', style: textos.titleMedium, maxLines: 1),
        ),
      ],
    );
  }
}
