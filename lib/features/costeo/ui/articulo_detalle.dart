import 'package:costeo/costeo.dart' as c;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../aplicar_precio.dart';
import '../costeo_notifiers.dart';
import '../costeo_provider.dart';
import '../insumo_model.dart';
import 'formato_costeo.dart';
import '../../../core/moneda.dart';

/// El detalle de un artículo: sus cuentas, su receta y sus parámetros. Todo
/// se edita acá y el catálogo se recalcula al guardar. La única escritura al
/// catálogo de productos es el botón "Aplicar precio", con confirmación.
Future<void> mostrarDetalleArticulo(BuildContext context, String clave) {
  return showDialog<void>(context: context, builder: (_) => _ArticuloDetalle(clave: clave));
}

class _ArticuloDetalle extends ConsumerWidget {
  const _ArticuloDetalle({required this.clave});
  final String clave;

  Future<void> _aplicarPrecio(BuildContext context, WidgetRef ref, ArticuloDelCatalogo catalogo, double precio) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('¿Aplicar el precio sugerido?'),
        contenido: Text(
          '${catalogo.nombre} pasa de ${colones(context, catalogo.precioActual)} a ${colones(context, precio)} en la carta. '
          'Solo este artículo; los demás no se tocan.',
        ),
        acciones: BentoAcciones(
          izquierda: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('No'))],
          derecha: [FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Aplicar'))],
        ),
      ),
    );
    if (confirmado != true || !context.mounted) return;
    await ref.read(aplicarPrecioProvider)(catalogo, precio);
    if (context.mounted) mostrarAviso(context, '✓ Precio aplicado a ${catalogo.nombre}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costeo = ref.watch(costeoProvider).valueOrNull;
    final calculado = costeo?.calculadoDe(clave);
    final catalogo = costeo?.articulos[clave];
    if (costeo == null || calculado == null || catalogo == null) {
      return const BentoDialogo(
        titulo: Text('Artículo'),
        contenido: Center(child: CircularProgressIndicator()),
        acciones: BentoAcciones(derecha: []),
      );
    }
    final textos = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    final a = calculado;
    final puedeAplicar = !a.precioFinal.isNaN && a.precioFinal > 0 && a.precioFinal != catalogo.precioActual;

    return BentoDialogo(
      titulo: Text(catalogo.nombre),
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cuentas(a: a, catalogo: catalogo),
          const SizedBox(height: BentoSpacing.gapCelda),
          _Receta(clave: clave, catalogo: catalogo, calculado: a),
          const SizedBox(height: BentoSpacing.gapCelda),
          _Parametros(catalogo: catalogo, calculado: a),
          if (a.alertas.isNotEmpty) ...[
            const SizedBox(height: BentoSpacing.gapCelda),
            for (final x in a.alertas)
              Text(
                x.esError ? '✗ ${x.mensaje}' : '· ${x.mensaje}',
                style: textos.bodySmall?.copyWith(color: x.esError ? error : null),
              ),
          ],
        ],
      ),
      acciones: BentoAcciones(
        izquierda: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar'))],
        derecha: [
          // Apagado cuando no hay nada que aplicar: sin precio calculable, o
          // ya se cobra exactamente eso. Es la única puerta al catálogo.
          FilledButton(
            onPressed: puedeAplicar ? () => _aplicarPrecio(context, ref, catalogo, a.precioFinal) : null,
            child: Text('Aplicar ${colones(context, a.precioFinal)}'),
          ),
        ],
      ),
    );
  }
}

class _Cuentas extends StatelessWidget {
  const _Cuentas({required this.a, required this.catalogo});
  final c.ArticuloCosteado a;
  final ArticuloDelCatalogo catalogo;

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    Widget fila(String etiqueta, String valor, {bool fuerte = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(etiqueta, style: textos.bodySmall)),
          Text(valor, style: fuerte ? textos.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : textos.bodySmall),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Por unidad', style: textos.labelLarge),
        fila('Insumos', colones(context, a.costoInsumosUnidad, decimales: 2)),
        fila('Mano de obra', colones(context, a.manoObraUnidad, decimales: 2)),
        if (a.articulo.otrosCostosDirectos > 0) fila('Otros directos', colones(context, a.articulo.otrosCostosDirectos, decimales: 2)),
        fila('Costos fijos que absorbe', colones(context, a.overheadUnidad, decimales: 2)),
        if (a.impuestoComprasUnidad > 0) fila('Impuesto simplificado (sobre compras)', colones(context, a.impuestoComprasUnidad, decimales: 2)),
        fila('Costo total', colones(context, a.costoTotalUnidad, decimales: 2), fuerte: true),
        const Divider(),
        fila('Precio sugerido (margen ${porcentaje(a.margenObjetivo)})', colones(context, a.precioSugerido, decimales: 2)),
        fila('Redondeado${a.articulo.ajustePrecio == 0 ? '' : ' y ajustado'}', colones(context, a.precioFinal), fuerte: true),
        fila('Se cobra hoy', colones(context, catalogo.precioActual), fuerte: true),
        if (a.articulo.tasaImpuesto > 0)
          fila('IVA dentro del precio (${porcentaje(a.articulo.tasaImpuesto)})', colones(context, a.impuestoPrecioUnidad, decimales: 2)),
        fila('Margen real al precio de hoy', porcentaje(a.margenReal)),
        if (a.foodCost != null)
          fila('Food cost (insumos ÷ precio)', '${porcentaje(a.foodCost)}${a.foodCost! > 0.38 ? ' — alto' : ''}'),
        fila(
          a.articulo.volumenEsReal ? 'Vendidas en $diasDeVolumen días' : 'Volumen estimado',
          '${a.articulo.unidadesMes} u',
        ),
      ],
    );
  }
}

/// La receta: una línea por insumo, con la cantidad POR LOTE.
class _Receta extends ConsumerWidget {
  const _Receta({required this.clave, required this.catalogo, required this.calculado});
  final String clave;
  final ArticuloDelCatalogo catalogo;
  final c.ArticuloCosteado calculado;

  Future<void> _editarLinea(BuildContext context, WidgetRef ref, {c.LineaCosteada? linea}) async {
    final insumos = (await ref.read(insumoNotifierProvider.future)).where((i) => i.activo).toList();
    if (!context.mounted) return;
    if (insumos.isEmpty) {
      mostrarAviso(context, 'Primero hay que crear insumos, en la sección Insumos');
      return;
    }
    final resultado = await showDialog<(String, double)>(
      context: context,
      builder: (_) => _LineaRecetaDialog(insumos: insumos, insumoId: linea?.insumoId, cantidad: linea?.cantidadPorLote),
    );
    if (resultado == null || !context.mounted) return;
    final registro = await ref.read(articuloCosteoProvider.notifier).asegurar(catalogo.producto.id, catalogo.variante?.id ?? '');
    await ref.read(articuloCosteoProvider.notifier).ponerLinea(registro.id, resultado.$1, resultado.$2);
  }

  Future<void> _quitarLinea(WidgetRef ref, String insumoId) async {
    final estado = await ref.read(articuloCosteoProvider.future);
    final registro = estado.articuloDe(catalogo.producto.id, catalogo.variante?.id ?? '');
    if (registro == null) return;
    final linea = estado.lineasDe(registro.id).where((l) => l.insumoId == insumoId).firstOrNull;
    if (linea != null) await ref.read(articuloCosteoProvider.notifier).quitarLinea(linea.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textos = Theme.of(context).textTheme;
    final insumos = ref.watch(insumoNotifierProvider).valueOrNull ?? const [];
    final porId = {for (final i in insumos) i.id: i};
    final lote = calculado.articulo.unidadesPorLote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Receta${lote > 1 ? ' (lote de $lote)' : ''}', style: textos.labelLarge)),
            TextButton.icon(
              onPressed: () => _editarLinea(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Insumo'),
            ),
          ],
        ),
        if (calculado.lineas.isEmpty)
          Text('Sin receta: el costo de insumos es cero.', style: textos.bodySmall)
        else
          for (final l in calculado.lineas)
            InkWell(
              onTap: () => _editarLinea(context, ref, linea: l),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${l.insumoNombre} · ${numero(l.cantidadPorLote)} ${porId[l.insumoId]?.unidadBase.abreviatura ?? ''}',
                        style: textos.bodyMedium,
                      ),
                    ),
                    Text(colones(context, l.costoLinea, decimales: 2), style: textos.bodySmall),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Quitar de la receta',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _quitarLinea(ref, l.insumoId),
                    ),
                  ],
                ),
              ),
            ),
        if (calculado.lineas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Insumos del lote: ${colones(context, calculado.costoInsumosLote, decimales: 2)}', style: textos.bodySmall),
          ),
      ],
    );
  }
}

class _LineaRecetaDialog extends StatefulWidget {
  const _LineaRecetaDialog({required this.insumos, this.insumoId, this.cantidad});
  final List<InsumoRegistro> insumos;
  final String? insumoId;
  final double? cantidad;

  @override
  State<_LineaRecetaDialog> createState() => _LineaRecetaDialogState();
}

class _LineaRecetaDialogState extends State<_LineaRecetaDialog> {
  late String _insumoId = widget.insumoId ?? widget.insumos.first.id;
  late final _cantidad = TextEditingController(text: widget.cantidad == null ? '' : numero(widget.cantidad!));

  @override
  void dispose() {
    _cantidad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insumo = widget.insumos.firstWhere((i) => i.id == _insumoId);
    return BentoDialogo(
      titulo: Text(widget.insumoId == null ? 'Insumo de la receta' : 'Cantidad'),
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _insumoId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Insumo'),
            items: [
              for (final i in widget.insumos)
                DropdownMenuItem(value: i.id, child: Text(i.nombre, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: widget.insumoId != null ? null : (v) => setState(() => _insumoId = v ?? _insumoId),
          ),
          const SizedBox(height: BentoSpacing.unidad),
          TextField(
            controller: _cantidad,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Cantidad por lote (${insumo.unidadBase.abreviatura})',
              helperText: 'Lo que lleva la tanda entera, no cada unidad',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      acciones: BentoAcciones(
        izquierda: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))],
        derecha: [
          FilledButton(
            onPressed: () {
              final n = parsearNumero(_cantidad.text);
              if (n == null || n <= 0) {
                mostrarAviso(context, '✗ La cantidad tiene que ser mayor que cero');
                return;
              }
              Navigator.of(context).pop((_insumoId, n));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

/// Los parámetros propios del artículo: lote, minutos, otros costos,
/// estimación de volumen, margen propio y ajuste.
class _Parametros extends ConsumerStatefulWidget {
  const _Parametros({required this.catalogo, required this.calculado});
  final ArticuloDelCatalogo catalogo;
  final c.ArticuloCosteado calculado;

  @override
  ConsumerState<_Parametros> createState() => _ParametrosState();
}

class _ParametrosState extends ConsumerState<_Parametros> {
  late final r = widget.catalogo.registro;
  late final _lote = TextEditingController(text: '${r?.unidadesPorLote ?? 1}');
  late final _minutos = TextEditingController(text: numero(r?.minutosLote ?? 0));
  late final _otros = TextEditingController(text: numero(r?.otrosCostosDirectos ?? 0));
  late final _estimadas = TextEditingController(text: '${r?.unidadesEstimadasMes ?? 0}');
  late final _margen = TextEditingController(text: r?.margenObjetivo == null ? '' : porcentajeParaEditar(r!.margenObjetivo!));
  late final _ajuste = TextEditingController(text: numero(r?.ajustePrecio ?? 0));
  bool _guardando = false;

  @override
  void dispose() {
    for (final c in [_lote, _minutos, _otros, _estimadas, _margen, _ajuste]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final lote = int.tryParse(_lote.text.trim());
    final minutos = parsearNumero(_minutos.text);
    final otros = parsearNumero(_otros.text);
    final estimadas = int.tryParse(_estimadas.text.trim());
    final margen = _margen.text.trim().isEmpty ? null : parsearPorcentaje(_margen.text);
    final ajuste = parsearNumero(_ajuste.text);
    if (lote == null || lote < 1 || minutos == null || minutos < 0 || otros == null || otros < 0 ||
        estimadas == null || estimadas < 0 || ajuste == null || (_margen.text.trim().isNotEmpty && margen == null)) {
      mostrarAviso(context, '✗ Revisá los números: lote ≥ 1, el resto no negativo');
      return;
    }
    setState(() => _guardando = true);
    final notifier = ref.read(articuloCosteoProvider.notifier);
    final registro = await notifier.asegurar(widget.catalogo.producto.id, widget.catalogo.variante?.id ?? '');
    await notifier.guardarArticulo(
      registro.copyWith(
        unidadesPorLote: lote,
        minutosLote: minutos,
        otrosCostosDirectos: otros,
        unidadesEstimadasMes: estimadas,
        margenObjetivo: margen,
        quitarMargen: margen == null,
        ajustePrecio: ajuste,
        updatedAt: DateTime.now(),
      ),
    );
    if (mounted) {
      setState(() => _guardando = false);
      mostrarAviso(context, '✓ Parámetros del artículo guardados');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textos = Theme.of(context).textTheme;
    Widget campo(TextEditingController c, String etiqueta, {String? ayuda, bool entero = false}) => Expanded(
      child: TextField(
        controller: c,
        decoration: InputDecoration(labelText: etiqueta, helperText: ayuda, helperMaxLines: 2, isDense: true),
        keyboardType: TextInputType.numberWithOptions(decimal: !entero, signed: !entero),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Parámetros del artículo', style: textos.labelLarge),
        const SizedBox(height: BentoSpacing.unidad / 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            campo(_lote, 'Unidades por lote', ayuda: 'Un molde da 12', entero: true),
            const SizedBox(width: BentoSpacing.unidad),
            campo(_minutos, 'Minutos del lote', ayuda: 'Tiempo de producirlo'),
          ],
        ),
        const SizedBox(height: BentoSpacing.unidad),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            campo(_otros, 'Otros directos (${Moneda.de(context).simbolo}/u)', ayuda: 'Etiqueta, maquila'),
            const SizedBox(width: BentoSpacing.unidad),
            campo(_estimadas, 'Estimadas al mes', ayuda: 'Solo si no hay ventas', entero: true),
          ],
        ),
        const SizedBox(height: BentoSpacing.unidad),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            campo(_margen, 'Margen propio (%)', ayuda: 'Vacío usa el de Ajustes'),
            const SizedBox(width: BentoSpacing.unidad),
            campo(_ajuste, 'Ajuste (${Moneda.de(context).simbolo}, con signo)', ayuda: '+ estrella, − gancho'),
          ],
        ),
        const SizedBox(height: BentoSpacing.unidad),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(onPressed: _guardando ? null : _guardar, child: const Text('Guardar parámetros')),
        ),
      ],
    );
  }
}
