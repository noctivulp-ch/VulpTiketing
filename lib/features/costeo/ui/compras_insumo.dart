import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../compra_insumo_model.dart';
import '../compra_insumo_notifier.dart';
import '../costo_de_insumos_provider.dart';
import '../insumo_model.dart';
import 'formato_costeo.dart';

const _uuid = Uuid();

/// Las compras de un insumo (0041): el costo que manda hoy y de dónde salió,
/// y la lista de entradas. "Anotar compra" es lo que se hace cada vez que se
/// abastece; editar el insumo es otra cosa y vive en su propio botón.
Future<void> mostrarComprasDeInsumo(BuildContext context, InsumoRegistro insumo) {
  return showDialog<void>(context: context, builder: (_) => _ComprasDeInsumo(insumo: insumo));
}

class _ComprasDeInsumo extends ConsumerWidget {
  const _ComprasDeInsumo({required this.insumo});
  final InsumoRegistro insumo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textos = Theme.of(context).textTheme;
    final costo = ref.watch(costoDeInsumosProvider).valueOrNull?[insumo.id];
    // Un año hacia atrás: es lo que cabe leer en un diálogo; lo anterior
    // vive en los libros y sigue contando para los totales.
    final hoy = DateTime.now();
    final rango = (DateTime(hoy.year - 1, hoy.month, hoy.day), DateTime(hoy.year, hoy.month, hoy.day + 1));
    final compras = ref.watch(comprasDeInsumosProvider(rango)).valueOrNull ?? const [];
    final propias = [for (final c in compras) if (c.insumoId == insumo.id) c];
    final u = insumo.unidadBase.abreviatura;

    return BentoDialogo(
      titulo: Text(insumo.nombre),
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (costo != null) ...[
            Text('${colones(costo.costoPorUnidadBase, decimales: 2)} por $u', style: textos.titleMedium),
            Text(costo.origen.texto, style: textos.bodySmall),
            if (insumo.merma != null)
              Text('con merma ${porcentaje(insumo.merma)}: ${colones(costo.costoPorUnidadBase / (1 - insumo.merma!), decimales: 2)} por $u', style: textos.bodySmall),
          ],
          const SizedBox(height: BentoSpacing.gapCelda),
          Row(
            children: [
              Expanded(child: Text('Compras del último año', style: textos.labelLarge)),
              TextButton.icon(
                onPressed: () => mostrarFormularioCompra(context, insumo),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Anotar compra'),
              ),
            ],
          ),
          if (propias.isEmpty)
            Text('Ninguna todavía. Mientras no haya, manda el precio de arranque del insumo.', style: textos.bodySmall)
          else
            for (final c in propias)
              InkWell(
                onTap: () => mostrarFormularioCompra(context, insumo, compra: c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(width: 78, child: Text(fechaCorta(c.fecha), style: textos.bodySmall)),
                      Expanded(
                        child: Text(
                          '${numero(c.presentaciones)} × ${numero(c.contenido)} $u'
                          '${c.notas == null ? '' : ' · ${c.notas}'}',
                          style: textos.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(colones(c.pagado), style: textos.bodyMedium),
                      const SizedBox(width: BentoSpacing.unidad),
                      Text('${colones(c.costoUnitario, decimales: 2)}/$u', style: textos.bodySmall),
                    ],
                  ),
                ),
              ),
        ],
      ),
      acciones: BentoAcciones(
        izquierda: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar'))],
        derecha: const [],
      ),
    );
  }
}

/// Anotar o corregir una compra. Con el ejemplo del dueño: "2 × 5.000 g por
/// ₡4.000". El contenido se precarga con el del insumo, que es lo habitual.
Future<void> mostrarFormularioCompra(BuildContext context, InsumoRegistro insumo, {CompraInsumo? compra}) {
  return showDialog<void>(context: context, builder: (_) => _CompraFormDialog(insumo: insumo, compra: compra));
}

class _CompraFormDialog extends ConsumerStatefulWidget {
  const _CompraFormDialog({required this.insumo, this.compra});
  final InsumoRegistro insumo;
  final CompraInsumo? compra;

  @override
  ConsumerState<_CompraFormDialog> createState() => _CompraFormDialogState();
}

class _CompraFormDialogState extends ConsumerState<_CompraFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _fecha = widget.compra?.fecha ?? DateTime.now();
  late final _presentaciones = TextEditingController(text: widget.compra == null ? '1' : numero(widget.compra!.presentaciones));
  late final _contenido = TextEditingController(
    text: numero(widget.compra?.contenido ?? widget.insumo.contenidoPorCompra),
  );
  late final _pagado = TextEditingController(text: widget.compra == null ? '' : numero(widget.compra!.pagado));
  late final _notas = TextEditingController(text: widget.compra?.notas ?? '');
  bool _ocupado = false;

  bool get _esEdicion => widget.compra != null;

  @override
  void dispose() {
    for (final c in [_presentaciones, _contenido, _pagado, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (elegida != null) setState(() => _fecha = DateTime(elegida.year, elegida.month, elegida.day, _fecha.hour, _fecha.minute));
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _ocupado = true);
    final compra = CompraInsumo(
      id: widget.compra?.id ?? _uuid.v4(),
      insumoId: widget.insumo.id,
      fecha: _fecha,
      presentaciones: parsearNumero(_presentaciones.text)!,
      contenido: parsearNumero(_contenido.text)!,
      pagado: parsearNumero(_pagado.text)!,
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
      updatedAt: DateTime.now(),
      deletedAt: widget.compra?.deletedAt,
    );
    final notifier = ref.read(compraInsumoNotifierProvider.notifier);
    await (_esEdicion ? notifier.corregir(compra) : notifier.anotar(compra));
    if (mounted) {
      Navigator.of(context).pop();
      mostrarAviso(context, '✓ Compra anotada: ${colones(compra.costoUnitario, decimales: 2)} por ${widget.insumo.unidadBase.abreviatura}');
    }
  }

  Future<void> _anular() async {
    setState(() => _ocupado = true);
    await ref.read(compraInsumoNotifierProvider.notifier).anular(widget.compra!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.insumo.unidadBase.abreviatura;
    final presentaciones = parsearNumero(_presentaciones.text) ?? 0;
    final contenido = parsearNumero(_contenido.text) ?? 0;
    final pagado = parsearNumero(_pagado.text) ?? 0;
    final unidades = presentaciones * contenido;
    return BentoDialogo(
      titulo: Text(_esEdicion ? 'Corregir compra' : 'Compra de ${widget.insumo.nombre}'),
      contenido: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _elegirFecha,
              icon: const Icon(Icons.event, size: 18),
              label: Text('Fecha: ${fechaCorta(_fecha)}'),
            ),
            const SizedBox(height: BentoSpacing.unidad),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _presentaciones,
                    autofocus: !_esEdicion,
                    decoration: const InputDecoration(labelText: 'Cuántas', helperText: 'Bultos, cajas…'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (parsearNumero(v ?? '') ?? 0) > 0 ? null : 'Mayor que cero',
                  ),
                ),
                const SizedBox(width: BentoSpacing.unidad),
                Expanded(
                  child: TextFormField(
                    controller: _contenido,
                    decoration: InputDecoration(labelText: 'De cuánto ($u)', helperText: 'Cada una'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (parsearNumero(v ?? '') ?? 0) > 0 ? null : 'Mayor que cero',
                  ),
                ),
              ],
            ),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(
              controller: _pagado,
              decoration: const InputDecoration(labelText: 'Pagado por todo (₡)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              validator: (v) => (parsearNumero(v ?? '') ?? -1) >= 0 ? null : 'Número inválido',
            ),
            const SizedBox(height: BentoSpacing.unidad / 2),
            // La cuenta a la vista mientras se escribe: es lo que evita anotar
            // 5 kg como 5 g.
            Text(
              unidades > 0 ? '${numero(unidades)} $u → ${colones(pagado / unidades, decimales: 2)} por $u' : '—',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(controller: _notas, decoration: const InputDecoration(labelText: 'Notas', helperText: 'Dónde, oferta, factura…')),
          ],
        ),
      ),
      acciones: BentoAcciones(
        izquierda: [
          TextButton(onPressed: _ocupado ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          if (_esEdicion) TextButton(onPressed: _ocupado ? null : _anular, child: const Text('Anular')),
        ],
        derecha: [FilledButton(onPressed: _ocupado ? null : _guardar, child: Text(_esEdicion ? 'Guardar' : 'Anotar'))],
      ),
    );
  }
}
