import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_corner_notice.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';
import '../../producto/producto_model.dart';
import '../../producto/producto_query_provider.dart';
import '../../producto/ui/producto_form_dialog.dart';
import '../linea_venta_model.dart';
import '../venta_en_curso_notifier.dart';

/// Ventana 2 — ver docs/pantallas/flujo-descripcion.md#ventana-2--panel-de-venta-carrito-completo
/// y docs/pantallas/prototipos-ascii.md. Carrito multi-línea + panel de
/// agregar producto (lista vertical, no cuadrícula — corregido tras
/// revisión del usuario).
class PanelVentaScreen extends ConsumerStatefulWidget {
  const PanelVentaScreen({super.key});

  @override
  ConsumerState<PanelVentaScreen> createState() => _PanelVentaScreenState();
}

class _PanelVentaScreenState extends ConsumerState<PanelVentaScreen> {
  bool _panelAbierto = false;

  @override
  Widget build(BuildContext context) {
    final carrito = _Carrito(onFinalizar: () => setState(() => _panelAbierto = false));
    final costura = _SeparadorConToggle(
      abierto: _panelAbierto,
      onTap: () => setState(() => _panelAbierto = !_panelAbierto),
    );

    // El panel se ACOPLA AL LADO LARGO: a la derecha cuando hay ancho, abajo
    // cuando no. Es el mismo panel persistente y el mismo botón de la costura,
    // rotados — no un overlay, que es lo que la decisión 0023 descarta.
    //
    // En teléfono la fila fija de antes repartía 3:4, o sea ~144 dp de carrito:
    // ahí no entra una línea de venta (miniatura 44 + nombre + subtotal + dos
    // botones de 48). Apilado, cada panel usa el ancho completo.
    if (BentoAncho.de(context).esCompacto) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(flex: _panelAbierto ? 2 : 1, child: carrito),
            costura,
            if (_panelAbierto) Expanded(flex: 3, child: _PanelAgregarProducto()),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: _panelAbierto ? 3 : 5,
            child: carrito,
          ),
          costura,
          if (_panelAbierto)
            Expanded(flex: 4, child: _PanelAgregarProducto()),
        ],
      ),
    );
  }
}

/// Costura entre el carrito y el panel de agregar producto — antes era solo
/// un ícono flotando sin fondo propio (no se leía como una separación real
/// entre los dos paneles, rompía la jerarquía). Ahora es una franja con tono
/// de fondo distinto a ambos paneles (separador real, no una línea) y el
/// botón que abre/cierra el panel vive anclado cerca del fondo de esa
/// franja — no centrado en toda la altura, y por encima de la barra inferior
/// del carrito (Recibí/Cambio/Total/Finalizar) para no estorbarla. El mismo
/// botón abre y cierra: se "arrastra" con el panel porque vive
/// estructuralmente en la costura, no en una posición fija.
class _SeparadorConToggle extends StatelessWidget {
  const _SeparadorConToggle({required this.abierto, required this.onTap});

  final bool abierto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final horizontal = BentoAncho.de(context).esCompacto;

    final boton = Material(
      color: scheme.primaryContainer,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.unidad),
          child: Icon(
            // El icono apunta hacia donde se va el panel: a la derecha cuando
            // la costura es vertical, hacia abajo cuando es horizontal.
            abierto
                ? (horizontal ? Icons.expand_more : Icons.chevron_right)
                : Icons.add_shopping_cart,
            size: 20,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );

    final fondo = ColoredBox(color: lacaDe(context).bandeja);

    // Costura horizontal: la franja cruza la pantalla y el botón va centrado.
    // No se puede anclar cerca de un extremo como en la vertical, porque acá el
    // extremo es un borde de pantalla y el pulgar no llega igual.
    if (horizontal) {
      return SizedBox(
        height: bentoObjetivoTactilMin,
        child: Stack(
          children: [
            Positioned.fill(child: fondo),
            Center(child: boton),
          ],
        ),
      );
    }

    return SizedBox(
      width: BentoSpacing.gapGrupo,
      child: Stack(
        children: [
          Positioned.fill(child: fondo),
          Positioned(
            left: 0,
            right: 0,
            bottom: BentoSpacing.gapGrupo * 3,
            child: Center(child: boton),
          ),
        ],
      ),
    );
  }
}

class _Carrito extends ConsumerStatefulWidget {
  const _Carrito({required this.onFinalizar});

  final VoidCallback onFinalizar;

  @override
  ConsumerState<_Carrito> createState() => _CarritoState();
}

class _CarritoState extends ConsumerState<_Carrito> {
  final _recibidoController = TextEditingController();
  double? _cambio;
  Timer? _debounce;
  bool _finalizando = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _recibidoController.dispose();
    super.dispose();
  }

  void _onRecibidoChanged(String valor, double total) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final recibido = double.tryParse(valor);
      setState(() => _cambio = recibido == null ? null : recibido - total);
    });
  }

  Future<void> _finalizar() async {
    setState(() => _finalizando = true);
    await ref.read(ventaEnCursoNotifierProvider.notifier).guardar();
    _recibidoController.clear();
    _cambio = null;
    if (mounted) {
      setState(() => _finalizando = false);
      mostrarNotificacionEsquina(context, '✓ Venta OK');
      widget.onFinalizar();
    }
  }

  Future<void> _editarLinea(LineaVenta linea) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DialogoEditarLinea(linea: linea),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ventaEnCurso = ref.watch(ventaEnCursoNotifierProvider);
    final productosAsync = ref.watch(productoQueryProvider);
    final productos = productosAsync.valueOrNull ?? const <Producto>[];
    final total = ventaEnCurso.total;

    return Column(
      children: [
        Expanded(
          child: ventaEnCurso.lineas.isEmpty
              ? const Center(child: Text('Agregá productos con el botón de la derecha'))
              : ListView.separated(
                  padding: const EdgeInsets.all(BentoSpacing.gapCelda),
                  itemCount: ventaEnCurso.lineas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: BentoSpacing.unidad),
                  itemBuilder: (context, i) {
                    final linea = ventaEnCurso.lineas[i];
                    final nombre = linea.nombreLibre ?? _buscarNombre(linea.productoId, productos);
                    return _FilaLineaVenta(
                      nombre: nombre,
                      lineaLibre: linea.nombreLibre != null,
                      cantidad: linea.cantidad,
                      nota: linea.nota,
                      subtotal: linea.precioAplicado * linea.cantidad,
                      onEditar: () => _editarLinea(linea),
                      onQuitar: () =>
                          ref.read(ventaEnCursoNotifierProvider.notifier).quitarLinea(linea.id),
                    );
                  },
                ),
        ),
        _BarraDeCobro(
          controlador: _recibidoController,
          cambio: _cambio,
          total: total,
          habilitado: ventaEnCurso.lineas.isNotEmpty && !_finalizando,
          onRecibidoChanged: (v) => _onRecibidoChanged(v, total),
          onFinalizar: _finalizar,
        ),
      ],
    );
  }

  String _buscarNombre(String? productoId, List<Producto> productos) {
    if (productoId == null) return 'Producto';
    for (final p in productos) {
      if (p.id == productoId) return p.nombre;
    }
    return 'Producto eliminado';
  }
}

/// Recibí · Cambio · Total · Finalizar.
///
/// En teléfono va en DOS filas de la retícula (3+3 y 3+3) en vez de una sola:
/// las cuatro piezas juntas eran el desborde más probable de la app, porque un
/// campo de texto, dos importes en colones y un botón no entran en 360 dp.
///
/// Sin `Material(elevation: 4)`: la sombra levantaba la barra de la bandeja
/// (DESIGN.md regla 1, prohibidas las sombras suaves — la escena de uso es sol
/// directo). El escalón lo marca ahora el pozo, como el resto de la app.
class _BarraDeCobro extends StatelessWidget {
  const _BarraDeCobro({
    required this.controlador,
    required this.cambio,
    required this.total,
    required this.habilitado,
    required this.onRecibidoChanged,
    required this.onFinalizar,
  });

  final TextEditingController controlador;
  final double? cambio;
  final double total;
  final bool habilitado;
  final ValueChanged<String> onRecibidoChanged;
  final VoidCallback onFinalizar;

  @override
  Widget build(BuildContext context) {
    final recibido = TextField(
      controller: controlador,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Recibí', isDense: true),
      onChanged: onRecibidoChanged,
    );
    final textoCambio = Align(
      alignment: Alignment.centerLeft,
      child: Text(cambio == null ? 'Cambio: —' : 'Cambio: ₡${cambio!.toStringAsFixed(2)}'),
    );
    final textoTotal = Align(
      alignment: Alignment.centerRight,
      child: Text(
        '₡${total.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
    final finalizar = FilledButton(
      onPressed: habilitado ? onFinalizar : null,
      child: const Text('Finalizar'),
    );

    return ColoredBox(
      color: lacaDe(context).pozo,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
          child: BentoCuadricula(
            hijos: [
              BentoCelda(compacto: 3, medio: 2, amplio: 2, hijo: recibido),
              BentoCelda(compacto: 3, medio: 2, amplio: 2, hijo: textoCambio),
              BentoCelda(compacto: 3, medio: 1, amplio: 1, hijo: textoTotal),
              BentoCelda(compacto: 3, medio: 1, amplio: 1, hijo: finalizar),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila del carrito — mismo lenguaje visual que `_TarjetaProducto` de
/// Ventana 1 (placeholder cuadrado + nombre + precio), en formato de fila
/// en vez de tarjeta porque aquí el contexto es una lista angosta, no un
/// grid (consistencia entre pantallas pedida por la skill
/// `aesthetic-usability`: la misma "pieza" de producto en toda la app).
class _FilaLineaVenta extends StatelessWidget {
  const _FilaLineaVenta({
    required this.nombre,
    required this.lineaLibre,
    required this.cantidad,
    required this.nota,
    required this.subtotal,
    required this.onEditar,
    required this.onQuitar,
  });

  final String nombre;
  final bool lineaLibre;
  final int cantidad;
  final String? nota;
  final double subtotal;
  final VoidCallback onEditar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.unidad),
      child: Row(
        children: [
          Container(
            width: bentoMiniatura,
            height: bentoMiniatura,
            decoration: BoxDecoration(
              color: lacaDe(context).pozoContacto,
              borderRadius: BorderRadius.circular(BentoRadius.pozo - BentoSpacing.unidad / 2),
            ),
            child: Icon(lineaLibre ? Icons.edit_note : Icons.image_outlined, size: 22),
          ),
          const SizedBox(width: BentoSpacing.unidad),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  'x$cantidad${nota != null && nota!.isNotEmpty ? ' · $nota' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text('₡${subtotal.toStringAsFixed(2)}', style: Theme.of(context).textTheme.labelLarge),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEditar),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onQuitar),
        ],
      ),
    );
  }
}

class _DialogoEditarLinea extends ConsumerStatefulWidget {
  const _DialogoEditarLinea({required this.linea});

  final LineaVenta linea;

  @override
  ConsumerState<_DialogoEditarLinea> createState() => _DialogoEditarLineaState();
}

class _DialogoEditarLineaState extends ConsumerState<_DialogoEditarLinea> {
  late final TextEditingController _precioController;
  late final TextEditingController _notaController;
  late int _cantidad;

  @override
  void initState() {
    super.initState();
    _precioController =
        TextEditingController(text: widget.linea.precioAplicado.toStringAsFixed(2));
    _notaController = TextEditingController(text: widget.linea.nota ?? '');
    _cantidad = widget.linea.cantidad;
  }

  @override
  void dispose() {
    _precioController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  void _guardar() {
    ref.read(ventaEnCursoNotifierProvider.notifier).editarLinea(
          widget.linea.id,
          precioAplicado: double.tryParse(_precioController.text),
          cantidad: _cantidad,
          nota: _notaController.text.trim().isEmpty ? null : _notaController.text.trim(),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar línea'),
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
                    onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
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
            controller: _notaController,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Lista vertical (no cuadrícula, ver decisión del usuario) de productos
/// disponibles. Toque simple agrega; mantener presionado entra en
/// selección múltiple.
class _PanelAgregarProducto extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PanelAgregarProducto> createState() => _PanelAgregarProductoState();
}

class _PanelAgregarProductoState extends ConsumerState<_PanelAgregarProducto> {
  final Set<String> _seleccionados = {};
  bool get _modoSeleccion => _seleccionados.isNotEmpty;

  void _agregarUno(Producto producto) {
    ref.read(ventaEnCursoNotifierProvider.notifier).agregarLineaDeCatalogo(
          productoId: producto.id,
          precioAplicado: producto.precioBase,
        );
  }

  void _agregarSeleccionados(List<Producto> productos) {
    for (final id in _seleccionados) {
      final producto = productos.where((p) => p.id == id).firstOrNull;
      if (producto != null) _agregarUno(producto);
    }
    setState(() => _seleccionados.clear());
  }

  Future<void> _lineaLibre() async {
    final nombreController = TextEditingController();
    final precioController = TextEditingController();
    final resultado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Línea libre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: precioController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (resultado != true) return;
    final nombre = nombreController.text.trim();
    final precio = double.tryParse(precioController.text);
    if (nombre.isEmpty || precio == null) return;
    ref.read(ventaEnCursoNotifierProvider.notifier).agregarLineaLibre(
          nombreLibre: nombre,
          precio: precio,
        );
  }

  @override
  Widget build(BuildContext context) {
    final productosAsync = ref.watch(productoQueryProvider);
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

    return Column(
      children: [
        // Cascada invertida: el buscador vive abajo (ver barra inferior), asi
        // que la lista crece hacia arriba desde ahi — con `reverse: true` el
        // primer resultado (mejor match, mismo orden que ya calculaba
        // productoQueryProvider) queda pegado al buscador, y el resto se aleja
        // hacia arriba en vez de leerse de arriba hacia abajo.
        Expanded(
          child: productosAsync.when(
            data: (productos) => ListView.separated(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: BentoSpacing.unidad),
              itemCount: productos.length,
              separatorBuilder: (_, _) => const SizedBox(height: BentoSpacing.unidad / 2),
              itemBuilder: (context, i) {
                final producto = productos[i];
                final seleccionado = _seleccionados.contains(producto.id);
                return ListTile(
                  leading: seleccionado ? const Icon(Icons.check_circle) : null,
                  title: Text(producto.nombre),
                  trailing: Text('₡${producto.precioBase.toStringAsFixed(2)}'),
                  selected: seleccionado,
                  onTap: () {
                    if (_modoSeleccion) {
                      setState(() {
                        seleccionado
                            ? _seleccionados.remove(producto.id)
                            : _seleccionados.add(producto.id);
                      });
                    } else {
                      _agregarUno(producto);
                    }
                  },
                  onLongPress: () => setState(() => _seleccionados.add(producto.id)),
                );
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
          ),
        ),
        if (_modoSeleccion)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BentoSpacing.unidad,
              vertical: BentoSpacing.unidad / 2,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text('Agregar (${_seleccionados.length})'),
                onPressed: () => _agregarSeleccionados(
                  productosAsync.valueOrNull ?? const [],
                ),
              ),
            ),
          ),
        // Barra inferior unificada: buscador + acciones en el mismo panel
        // (antes el buscador vivia arriba, separado de estos botones).
        ColoredBox(
          color: lacaDe(context).pozo,
          child: Padding(
            padding: const EdgeInsets.all(BentoSpacing.unidad),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar producto o categoría…',
                      isDense: true,
                    ),
                    onChanged: (v) => ref.read(productoBusquedaProvider.notifier).state = v,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.note_add_outlined),
                  tooltip: 'Línea libre',
                  onPressed: _lineaLibre,
                ),
                if (esGerente)
                  IconButton(
                    icon: const Icon(Icons.add_box_outlined),
                    tooltip: 'Producto nuevo al vuelo',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ProductoFormDialog(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
