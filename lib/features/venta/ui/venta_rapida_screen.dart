import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_corner_notice.dart';
import '../../../core/theme/bento_theme.dart';
import '../../producto/producto_model.dart';
import '../../producto/producto_query_provider.dart';
import '../venta_en_curso_notifier.dart';

/// Ventana 1 — ver docs/pantallas/flujo-descripcion.md#ventana-1--venta-rápida
/// y docs/pantallas/prototipos-ascii.md. Crea una Venta de una sola línea
/// reutilizando VentaEnCursoNotifier (mismo modelo que la Ventana 2, ruta de
/// UI más corta para el caso de un producto).
class VentaRapidaScreen extends ConsumerWidget {
  const VentaRapidaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productosAsync = ref.watch(productoQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar producto o categoría…',
            border: InputBorder.none,
          ),
          onChanged: (v) => ref.read(productoBusquedaProvider.notifier).state = v,
        ),
      ),
      body: productosAsync.when(
        data: (productos) => productos.isEmpty
            ? const Center(child: Text('Sin productos'))
            : GridView.builder(
                padding: const EdgeInsets.all(BentoSpacing.gapCelda),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: BentoSpacing.gapCelda,
                  crossAxisSpacing: BentoSpacing.gapCelda,
                  childAspectRatio: 0.85,
                ),
                itemCount: productos.length,
                itemBuilder: (context, i) {
                  final producto = productos[i];
                  return _TarjetaProducto(
                    producto: producto,
                    onTap: () => _abrirCobroRapido(context, ref, producto),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _abrirCobroRapido(
    BuildContext context,
    WidgetRef ref,
    Producto producto,
  ) async {
    final completado = await showDialog<bool>(
      context: context,
      builder: (_) => _OverlayCobroRapido(producto: producto),
    );
    if (completado == true && context.mounted) {
      mostrarNotificacionEsquina(context, '✓ Venta OK');
    }
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto, required this.onTap});

  final Producto producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BentoRadius.celda),
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.unidad * 1.5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(BentoRadius.celda - BentoSpacing.unidad / 2),
                  ),
                  child: const Center(child: Icon(Icons.image_outlined, size: 32)),
                ),
              ),
              const SizedBox(height: BentoSpacing.unidad),
              Text(
                producto.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                '₡${producto.precioBase.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlay de cobro de un solo producto (0018 cantidad default 1, precio
/// editable con el base como punto de partida, cambio con debounce 400ms
/// — ver decisiones ya cerradas en flujo-descripcion.md).
class _OverlayCobroRapido extends ConsumerStatefulWidget {
  const _OverlayCobroRapido({required this.producto});

  final Producto producto;

  @override
  ConsumerState<_OverlayCobroRapido> createState() => _OverlayCobroRapidoState();
}

class _OverlayCobroRapidoState extends ConsumerState<_OverlayCobroRapido> {
  late final TextEditingController _precioController;
  final _recibidoController = TextEditingController();
  int _cantidad = 1;
  double? _cambio;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _precioController =
        TextEditingController(text: widget.producto.precioBase.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _precioController.dispose();
    _recibidoController.dispose();
    super.dispose();
  }

  void _onRecibidoChanged(String valor) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final recibido = double.tryParse(valor);
      final precio = double.tryParse(_precioController.text) ?? 0;
      setState(() {
        _cambio = recibido == null ? null : recibido - (precio * _cantidad);
      });
    });
  }

  Future<void> _completar() async {
    final precio = double.tryParse(_precioController.text) ?? widget.producto.precioBase;
    ref.read(ventaEnCursoNotifierProvider.notifier).agregarLineaDeCatalogo(
          productoId: widget.producto.id,
          precioAplicado: precio,
          cantidad: _cantidad,
        );
    await ref.read(ventaEnCursoNotifierProvider.notifier).guardar();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.producto.nombre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cantidad'),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _cantidad > 1
                        ? () => setState(() => _cantidad--)
                        : null,
                  ),
                  Text('$_cantidad'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _cantidad++),
                  ),
                ],
              ),
            ],
          ),
          TextField(
            controller: _precioController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio'),
          ),
          TextField(
            controller: _recibidoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Recibí'),
            onChanged: _onRecibidoChanged,
          ),
          const SizedBox(height: BentoSpacing.unidad),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_cambio == null ? 'Cambio: —' : 'Cambio: ₡${_cambio!.toStringAsFixed(2)}'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _completar, child: const Text('Completado')),
      ],
    );
  }
}
