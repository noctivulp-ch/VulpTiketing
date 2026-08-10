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
/// **Solo se puede pulsar el que toca.** El día va en orden: apertura, medio día,
/// cierre. Los anteriores están hechos y los posteriores no han llegado, así que
/// aparecen los tres —para que se vea en qué punto va la jornada— pero solo uno
/// responde. Lo que habilita el siguiente es haber anotado el anterior, no la
/// hora: el cambio de turno cae entre las 12 y las 2:30 según el día.
Future<CorteAnotado?> mostrarDialogoDeCorte(
  BuildContext context, {
  required MomentoCorte siguiente,
}) {
  return showDialog<CorteAnotado>(
    context: context,
    builder: (_) => _DialogoCorte(siguiente: siguiente),
  );
}

class _DialogoCorte extends StatefulWidget {
  const _DialogoCorte({required this.siguiente});

  final MomentoCorte siguiente;

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

  void _anotar() {
    if (_formulario.currentState?.validate() != true) return;
    Navigator.of(
      context,
    ).pop(CorteAnotado(momento: widget.siguiente, monto: double.parse(_monto.text.trim())));
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
                  momento == widget.siguiente
                      ? FilledButton(onPressed: _anotar, child: Text(nombreDeMomento(momento)))
                      : OutlinedButton(onPressed: null, child: Text(nombreDeMomento(momento))),
              ],
            ),
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
