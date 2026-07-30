import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_corner_notice.dart';
import '../../../core/theme/bento_tallado.dart';
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

    // Una sola bandeja: el buscador y el grid son pozos tallados en ella,
    // separados por paredes de material. Sin AppBar — la barra superior de
    // Material seria una pieza pegada ENCIMA de la bandeja, no un hueco
    // dentro (DESIGN.md, regla 8).
    return Scaffold(
      body: BentoBandeja(
        child: Column(
          children: [
            // El buscador es herramienta, no contenido: pozo bajo y denso para
            // que no compita en peso con una fila del grid.
            BentoPozo(
              padding: const EdgeInsets.symmetric(horizontal: BentoSpacing.paddingCelda),
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar producto o categoría…',
                  border: InputBorder.none,
                ),
                onChanged: (v) => ref.read(productoBusquedaProvider.notifier).state = v,
              ),
            ),
            const SizedBox(height: BentoSpacing.pared),
            Expanded(
              child: productosAsync.when(
                data: (productos) => productos.isEmpty
                    ? const _SinProductos()
                    : GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          mainAxisSpacing: BentoSpacing.pared,
                          crossAxisSpacing: BentoSpacing.pared,
                          // Mas ancho que alto: sin hueco de imagen el pozo
                          // solo tiene que sostener nombre y precio, y una
                          // celda alta dejaba un vacio muerto en el medio.
                          childAspectRatio: 1.25,
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
            ),
          ],
        ),
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

/// Estado vacio que enseña la interfaz en vez de decir "no hay nada"
/// (bandeja recien puesta, todavia sin compartimentos servidos).
class _SinProductos extends StatelessWidget {
  const _SinProductos();

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'La bandeja está vacía',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: laca.textoEnBandeja),
          ),
          const SizedBox(height: BentoSpacing.unidad),
          Text(
            'Agregá productos en Catálogo, o importá el menú desde Configuración.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: laca.textoAtenuadoEnBandeja,
                ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto, required this.onTap});

  final Producto producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final laca = lacaDe(context);
    final tema = Theme.of(context);
    final tieneImagen = producto.imagen != null;

    return BentoPozo(
      onTap: onTap,
      padding: const EdgeInsets.all(BentoSpacing.unidad * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sin imagen no se reserva el hueco: un rebaje vacio con un icono
          // generico se comia el 60% de la celda para no decir nada. Lo que
          // se lee al cobrar es el nombre y el precio, asi que ellos ocupan
          // el compartimento.
          if (tieneImagen)
            Expanded(
              // Rebaje mas profundo DENTRO del pozo, no una tarjeta anidada:
              // es el platito metido en el compartimento (referencias
              // visuales, fotos 2 y 5), de ahi el tono de sombra de contacto.
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: laca.pozoContacto,
                  borderRadius: BorderRadius.circular(BentoRadius.pozo / 2),
                ),
                child: Center(
                  child: Icon(Icons.image_outlined, size: 32, color: laca.paredCresta),
                ),
              ),
            ),
          if (tieneImagen) const SizedBox(height: BentoSpacing.unidad),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: BentoTextoTallado(
                producto.nombre,
                sobre: laca.pozo,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                estilo: tema.textTheme.bodyLarge,
              ),
            ),
          ),
          const SizedBox(height: BentoSpacing.unidad / 2),
          // El precio es el dato que decide la accion, asi que su jerarquia la
          // dan el tamano y el peso — NO se le baja el contraste. Con nivel
          // `marcado` quedaba mas apagado que el nombre del producto, o sea
          // invertia la jerarquia: el tallado se comia justo lo que tenia que
          // destacar. `marcado` queda reservado para los numeros de 40px de
          // Reportes, donde el tamano lo sostiene solo.
          BentoTextoTallado(
            '₡${producto.precioBase.toStringAsFixed(0)}',
            sobre: laca.pozo,
            estilo: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
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
