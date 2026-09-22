import 'package:costeo/costeo.dart' as c;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/ui/bento_falla.dart';
import '../costeo_notifiers.dart';
import '../costo_de_insumos_provider.dart';
import '../insumo_model.dart';
import 'compras_insumo.dart';
import 'formato_costeo.dart';

const _uuid = Uuid();

/// El catálogo de materias primas y sus compras (0041). El insumo se
/// registra una vez; cada vez que se abastece se anota una compra, y el
/// costo que usan las recetas sale del promedio de las compras recientes.
/// Tocar un insumo abre sus compras; el lápiz edita el maestro.
class InsumosPanel extends ConsumerWidget {
  const InsumosPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insumos = ref.watch(insumoNotifierProvider);
    final config = ref.watch(configCosteoProvider).valueOrNull ?? const c.ConfigCosteo();
    final costos = ref.watch(costoDeInsumosProvider).valueOrNull ?? const {};
    final textos = Theme.of(context).textTheme;
    final hoy = DateTime.now();
    final mes = (DateTime(hoy.year, hoy.month), DateTime(hoy.year, hoy.month + 1));
    final trimestre = (DateTime(hoy.year, ((hoy.month - 1) ~/ 3) * 3 + 1), DateTime(hoy.year, ((hoy.month - 1) ~/ 3) * 3 + 4));
    final compradoMes = ref.watch(totalComprasProvider(mes)).valueOrNull;
    final compradoTrimestre = ref.watch(totalComprasProvider(trimestre)).valueOrNull;
    return insumos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => BentoFalla(mensaje: 'No se pudieron leer los insumos.', error: e),
      data: (lista) {
        final activos = [for (final i in lista) if (i.activo) i];
        return Column(
          children: [
            Expanded(
              child: activos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(BentoSpacing.rim),
                        child: Text(
                          'Sin insumos. Cada uno se compra en una presentación (un bulto, una caja) '
                          'y se usa en gramos, mililitros o unidades.',
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
                        final insumo = activos[i];
                        final costo = costos[insumo.id];
                        final base = costo?.costoPorUnidadBase ?? insumo.puro.costoPorUnidadBase;
                        final merma = insumo.merma ?? config.mermaPorDefecto;
                        final efectivo = merma >= 1 ? double.infinity : base / (1 - merma);
                        return BentoPozo(
                          onTap: () => mostrarComprasDeInsumo(context, insumo),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(insumo.nombre, style: textos.titleSmall),
                                    Text(
                                      '${costo?.origen.texto ?? OrigenDelCosto.arranque.texto}'
                                      '${insumo.merma == null ? '' : ' · merma ${porcentaje(insumo.merma)}'}'
                                      '${insumo.proveedor == null ? '' : ' · ${insumo.proveedor}'}',
                                      style: textos.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(colones(efectivo, decimales: 2), style: textos.titleSmall),
                                  Text('por ${insumo.unidadBase.abreviatura}, con merma', style: textos.bodySmall),
                                ],
                              ),
                              IconButton(
                                tooltip: 'Editar ${insumo.nombre}',
                                onPressed: () => mostrarFormularioInsumo(context, insumo: insumo),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            // Lo comprado: la cifra de "cuánto se gasta", y en el régimen
            // simplificado la base del impuesto del trimestre.
            _BarraInferior(
              texto: compradoMes == null
                  ? '${activos.length} insumo(s)'
                  : 'Comprado: mes ${colones(compradoMes)} · trimestre ${colones(compradoTrimestre ?? 0)}',
              accion: 'Nuevo insumo',
              onAccion: () => mostrarFormularioInsumo(context),
            ),
          ],
        );
      },
    );
  }
}

/// La barra de abajo de cada sección: un conteo y el botón de crear. Misma
/// forma que la barra del Catálogo.
class _BarraInferior extends StatelessWidget {
  const _BarraInferior({required this.texto, required this.accion, required this.onAccion});
  final String texto;
  final String accion;
  final VoidCallback onAccion;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: lacaDe(context).pozo,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.unidad),
          child: Row(
            children: [
              Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyMedium)),
              FilledButton.icon(onPressed: onAccion, icon: const Icon(Icons.add), label: Text(accion)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> mostrarFormularioInsumo(BuildContext context, {InsumoRegistro? insumo}) {
  return showDialog<void>(context: context, builder: (_) => _InsumoFormDialog(insumo: insumo));
}

class _InsumoFormDialog extends ConsumerStatefulWidget {
  const _InsumoFormDialog({this.insumo});
  final InsumoRegistro? insumo;

  @override
  ConsumerState<_InsumoFormDialog> createState() => _InsumoFormDialogState();
}

class _InsumoFormDialogState extends ConsumerState<_InsumoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.insumo?.nombre ?? '');
  late final _contenido = TextEditingController(
    text: widget.insumo == null ? '' : numero(widget.insumo!.contenidoPorCompra),
  );
  late final _precio = TextEditingController(text: widget.insumo == null ? '' : numero(widget.insumo!.precioCompra));
  late final _merma = TextEditingController(
    text: widget.insumo?.merma == null ? '' : porcentajeParaEditar(widget.insumo!.merma!),
  );
  late final _proveedor = TextEditingController(text: widget.insumo?.proveedor ?? '');
  late final _notas = TextEditingController(text: widget.insumo?.notas ?? '');
  late c.UnidadBase _unidad = widget.insumo?.unidadBase ?? c.UnidadBase.gramo;
  bool _ocupado = false;

  bool get _esEdicion => widget.insumo != null;

  @override
  void dispose() {
    for (final c in [_nombre, _contenido, _precio, _merma, _proveedor, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _ocupado = true);
    final registro = InsumoRegistro(
      id: widget.insumo?.id ?? _uuid.v4(),
      nombre: _nombre.text.trim(),
      unidadBase: _unidad,
      contenidoPorCompra: parsearNumero(_contenido.text)!,
      precioCompra: parsearNumero(_precio.text)!,
      merma: _merma.text.trim().isEmpty ? null : parsearPorcentaje(_merma.text),
      proveedor: _proveedor.text.trim().isEmpty ? null : _proveedor.text.trim(),
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
      updatedAt: DateTime.now(),
      deletedAt: widget.insumo?.deletedAt,
    );
    final notifier = ref.read(insumoNotifierProvider.notifier);
    await (_esEdicion ? notifier.actualizar(registro) : notifier.crear(registro));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _descontinuar() async {
    setState(() => _ocupado = true);
    await ref.read(insumoNotifierProvider.notifier).descontinuar(widget.insumo!.id);
    if (mounted) {
      Navigator.of(context).pop();
      mostrarAviso(context, '✓ Insumo fuera del catálogo; las recetas que lo usen lo avisan');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BentoDialogo(
      titulo: Text(_esEdicion ? 'Editar insumo' : 'Nuevo insumo'),
      contenido: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nombre,
              autofocus: !_esEdicion,
              decoration: const InputDecoration(labelText: 'Nombre'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: BentoSpacing.unidad),
            // Unidad y contenido juntos: "un bulto de 1000 g". El puente entre
            // lo que se compra y lo que se usa es esta pareja.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<c.UnidadBase>(
                    initialValue: _unidad,
                    decoration: const InputDecoration(labelText: 'Se usa en'),
                    items: [
                      for (final u in c.UnidadBase.values)
                        DropdownMenuItem(value: u, child: Text('${u.nombre}s (${u.abreviatura})')),
                    ],
                    onChanged: (u) => setState(() => _unidad = u ?? _unidad),
                  ),
                ),
                const SizedBox(width: BentoSpacing.unidad),
                Expanded(
                  child: TextFormField(
                    controller: _contenido,
                    decoration: InputDecoration(labelText: 'Trae (${_unidad.abreviatura})', helperText: 'Por compra'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = parsearNumero(v ?? '');
                      return (n == null || n <= 0) ? 'Mayor que cero' : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(
              controller: _precio,
              decoration: const InputDecoration(
                labelText: 'Precio de arranque (₡)',
                helperText: 'Lo que se paga por esa presentación. Manda solo hasta la primera compra anotada',
                helperMaxLines: 2,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = parsearNumero(v ?? '');
                return (n == null || n < 0) ? 'Número inválido' : null;
              },
            ),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(
              controller: _merma,
              decoration: const InputDecoration(
                labelText: 'Merma (%)',
                helperText: 'Lo que se pierde: se cae, se pega, se vence. Vacío usa la de Ajustes',
                helperMaxLines: 2,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = parsearNumero(v);
                return (n == null || n < 0 || n >= 100) ? 'Entre 0 y 99' : null;
              },
            ),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(controller: _proveedor, decoration: const InputDecoration(labelText: 'Proveedor')),
            const SizedBox(height: BentoSpacing.unidad),
            TextFormField(controller: _notas, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2),
          ],
        ),
      ),
      acciones: BentoAcciones(
        izquierda: [
          TextButton(onPressed: _ocupado ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          if (_esEdicion) TextButton(onPressed: _ocupado ? null : _descontinuar, child: const Text('Quitar')),
        ],
        derecha: [FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar'))],
      ),
    );
  }
}
