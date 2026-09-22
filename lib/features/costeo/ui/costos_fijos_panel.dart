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
import '../../../core/moneda.dart';

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
                              Text('${colones(context, f.montoMensual)} / mes', style: textos.titleSmall),
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
                      Expanded(child: Text('Total ${colones(context, total)} / mes', style: textos.titleSmall)),
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
  // Amortizar: un total ya pagado (el desarrollo de una app, un horno)
  // repartido en meses. No se guarda: es una calculadora que rellena el monto.
  final _total = TextEditingController();
  final _meses = TextEditingController(text: '12');
  bool _amortizar = false;
  bool _ocupado = false;

  void _calcularAmortizacion() {
    final total = parsearNumero(_total.text);
    final meses = int.tryParse(_meses.text.trim());
    if (total == null || meses == null || meses <= 0) return;
    setState(() => _monto.text = numero(total / meses));
  }

  bool get _esEdicion => widget.costo != null;

  @override
  void dispose() {
    _concepto.dispose();
    _monto.dispose();
    _notas.dispose();
    _total.dispose();
    _meses.dispose();
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
              decoration: InputDecoration(labelText: 'Monto mensual ${Moneda.de(context).entreParentesis}'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = parsearNumero(v ?? '');
                return (n == null || n < 0) ? 'Número inválido' : null;
              },
            ),
            // Un total ya pagado repartido en meses: es como un negocio de
            // servicios lleva el desarrollo, y como cualquiera lleva un horno.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _amortizar,
              onChanged: (v) => setState(() => _amortizar = v),
              title: const Text('Calcular desde un total (amortizar)'),
              subtitle: const Text('Horas × tarifa del desarrollo, o el precio de un equipo, entre los meses'),
            ),
            if (_amortizar)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _total,
                      decoration: InputDecoration(labelText: 'Total ${Moneda.de(context).entreParentesis}', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _calcularAmortizacion(),
                    ),
                  ),
                  const SizedBox(width: BentoSpacing.unidad),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _meses,
                      decoration: const InputDecoration(labelText: 'Meses', isDense: true),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _calcularAmortizacion(),
                    ),
                  ),
                ],
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
