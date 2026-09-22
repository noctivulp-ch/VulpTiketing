import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/ui/bento_falla.dart';
import '../costeo_notifiers.dart';
import '../costo_fijo_model.dart';
import 'formato_costeo.dart';

const _uuid = Uuid();

/// Lo que se paga aunque no se venda nada: alquiler, servicios, sueldos.
/// Repartirlo entre las unidades del mes es lo que convierte un costo del
/// negocio en un costo del producto.
class CostosFijosPanel extends ConsumerWidget {
  const CostosFijosPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fijos = ref.watch(costoFijoNotifierProvider);
    final textos = Theme.of(context).textTheme;
    return fijos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => BentoFalla(mensaje: 'No se pudieron leer los costos fijos.', error: e),
      data: (lista) {
        final activos = [for (final f in lista) if (f.activo) f];
        final total = activos.fold(0.0, (s, f) => s + f.montoMensual);
        return Column(
          children: [
            Expanded(
              child: activos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(BentoSpacing.rim),
                        child: Text(
                          'Sin costos fijos. Sin ellos, los precios sugeridos solo cubren insumos y '
                          'mano de obra — y el alquiler lo paga nadie.',
                          textAlign: TextAlign.center,
                          style: textos.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(BentoSpacing.gapCelda),
                      itemCount: activos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: BentoSpacing.unidad),
                      itemBuilder: (context, i) {
                        final f = activos[i];
                        return BentoPozo(
                          onTap: () => mostrarFormularioCostoFijo(context, costo: f),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f.concepto, style: textos.titleSmall),
                                    if (f.notas != null) Text(f.notas!, style: textos.bodySmall),
                                  ],
                                ),
                              ),
                              Text('${colones(f.montoMensual)} / mes', style: textos.titleSmall),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            ColoredBox(
              color: lacaDe(context).pozo,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(BentoSpacing.unidad),
                  child: Row(
                    children: [
                      Expanded(child: Text('Total ${colones(total)} / mes', style: textos.titleSmall)),
                      FilledButton.icon(
                        onPressed: () => mostrarFormularioCostoFijo(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo costo'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> mostrarFormularioCostoFijo(BuildContext context, {CostoFijoRegistro? costo}) {
  return showDialog<void>(context: context, builder: (_) => _CostoFijoFormDialog(costo: costo));
}

class _CostoFijoFormDialog extends ConsumerStatefulWidget {
  const _CostoFijoFormDialog({this.costo});
  final CostoFijoRegistro? costo;

  @override
  ConsumerState<_CostoFijoFormDialog> createState() => _CostoFijoFormDialogState();
}

class _CostoFijoFormDialogState extends ConsumerState<_CostoFijoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _concepto = TextEditingController(text: widget.costo?.concepto ?? '');
  late final _monto = TextEditingController(text: widget.costo == null ? '' : numero(widget.costo!.montoMensual));
  late final _notas = TextEditingController(text: widget.costo?.notas ?? '');
  bool _ocupado = false;

  bool get _esEdicion => widget.costo != null;

  @override
  void dispose() {
    _concepto.dispose();
    _monto.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _ocupado = true);
    final registro = CostoFijoRegistro(
      id: widget.costo?.id ?? _uuid.v4(),
      concepto: _concepto.text.trim(),
      montoMensual: parsearNumero(_monto.text)!,
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
      updatedAt: DateTime.now(),
      deletedAt: widget.costo?.deletedAt,
    );
    final notifier = ref.read(costoFijoNotifierProvider.notifier);
    await (_esEdicion ? notifier.actualizar(registro) : notifier.crear(registro));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _quitar() async {
    setState(() => _ocupado = true);
    await ref.read(costoFijoNotifierProvider.notifier).descontinuar(widget.costo!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BentoDialogo(
      titulo: Text(_esEdicion ? 'Editar costo fijo' : 'Nuevo costo fijo'),
      contenido: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _concepto,
              autofocus: !_esEdicion,
              decoration: const InputDecoration(labelText: 'Concepto', helperText: 'Alquiler, luz, agua, sueldo, internet…'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(
              controller: _monto,
              decoration: const InputDecoration(labelText: 'Monto mensual (₡)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = parsearNumero(v ?? '');
                return (n == null || n < 0) ? 'Número inválido' : null;
              },
            ),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(controller: _notas, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2),
          ],
        ),
      ),
      acciones: BentoAcciones(
        izquierda: [
          TextButton(onPressed: _ocupado ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          if (_esEdicion) TextButton(onPressed: _ocupado ? null : _quitar, child: const Text('Quitar')),
        ],
        derecha: [FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar'))],
      ),
    );
  }
}
