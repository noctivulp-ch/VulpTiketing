import 'package:flutter/material.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../corte_caja_model.dart';

class CorteAnotado {
  const CorteAnotado({required this.momento, required this.monto});

  final MomentoCorte momento;
  final double monto;
}

/// Pide el monto y en qué momento del día se está anotando.
///
/// Los tres momentos son botones y no una lista desplegable porque son tres y
/// se ven de un golpe — así lo pidió el dueño y así se lee sin abrir nada.
///
/// **Se pueden pulsar dos: el que toca y el último anotado.** El día va en
/// orden: apertura, medio día, cierre; lo que habilita el siguiente es haber
/// anotado el anterior, no la hora, porque el cambio de turno cae entre las 12 y
/// las 2:30 según el día. Los tres se dibujan siempre para que se vea en qué
/// punto va la jornada.
///
/// El último se puede volver a pulsar para **corregirlo**, y eso entró porque el
/// diseño sin corrección falló en el primer uso: un cierre anotado con un 5 y
/// quince ceros dejó el día en ₡5 000 000 000 000 000 sin salida. Solo el
/// último: los anteriores ya sirvieron de frontera para el efectivo que se contó
/// después.
Future<CorteAnotado?> mostrarDialogoDeCorte(
  BuildContext context, {
  required MomentoCorte? siguiente,
  required MomentoCorte? ultimo,
  required double montoDelUltimo,
}) {
  return showDialog<CorteAnotado>(
    context: context,
    builder: (_) =>
        _DialogoCorte(siguiente: siguiente, ultimo: ultimo, montoDelUltimo: montoDelUltimo),
  );
}

class _DialogoCorte extends StatefulWidget {
  const _DialogoCorte({
    required this.siguiente,
    required this.ultimo,
    required this.montoDelUltimo,
  });

  /// El que toca anotar, o `null` si el día ya se cerró — ahí solo se puede
  /// corregir el cierre.
  final MomentoCorte? siguiente;

  /// El último anotado, o `null` si todavía no hay ninguno.
  final MomentoCorte? ultimo;

  final double montoDelUltimo;

  @override
  State<_DialogoCorte> createState() => _DialogoCorteState();
}

class _DialogoCorteState extends State<_DialogoCorte> {
  final _monto = TextEditingController();
  final _formulario = GlobalKey<FormState>();

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  void _anotar(MomentoCorte momento) {
    if (_formulario.currentState?.validate() != true) return;
    Navigator.of(
      context,
    ).pop(CorteAnotado(momento: momento, monto: double.parse(_monto.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;

    return BentoDialogo(
      titulo: const Text('Caja Inicial'),
      contenido: Form(
        key: _formulario,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Monto', style: textos.bodyMedium),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(
              controller: _monto,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Lo que queda en la caja (₡)'),
              validator: (v) {
                final texto = v?.trim() ?? '';
                if (texto.isEmpty) return 'Requerido';
                final monto = double.tryParse(texto);
                if (monto == null) return 'Número inválido';
                // Se admite cero: al cerrar se puede dejar la caja vacía. Lo que
                // no tiene lectura posible es un monto negativo.
                if (monto < 0) return 'No puede ser negativo';
                return null;
              },
            ),
            const SizedBox(height: BentoSpacing.gapCelda),
            Text('Cierre', style: textos.bodyMedium),
            const SizedBox(height: BentoSpacing.unidad),
            Wrap(
              spacing: BentoSpacing.unidad,
              runSpacing: BentoSpacing.unidad,
              children: [
                for (final momento in MomentoCorte.values)
                  if (momento == widget.siguiente)
                    FilledButton(
                      onPressed: () => _anotar(momento),
                      child: Text(nombreDeMomento(momento)),
                    )
                  else if (momento == widget.ultimo)
                    // Contorneado y no relleno: corregir es la salida de
                    // emergencia, no el camino normal. Si los dos se vieran
                    // igual, el de corregir competiría con el que toca.
                    OutlinedButton(
                      onPressed: () => _anotar(momento),
                      child: Text(nombreDeMomento(momento)),
                    )
                  else
                    OutlinedButton(onPressed: null, child: Text(nombreDeMomento(momento))),
              ],
            ),
            if (widget.ultimo != null) ...[
              const SizedBox(height: BentoSpacing.unidad),
              // Se dice el monto que se va a reemplazar, no un "podés corregir"
              // genérico: el número es lo que permite ver si el que está mal es
              // ese, y sin él hay que salir a mirarlo al cuadro.
              Text(
                'Volver a pulsar ${nombreDeMomento(widget.ultimo!)} '
                'reemplaza su conteo de ₡${widget.montoDelUltimo.toStringAsFixed(2)}',
                style: textos.bodySmall,
              ),
            ],
          ],
        ),
      ),
      acciones: BentoAcciones(
        derecha: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ],
      ),
    );
  }
}
