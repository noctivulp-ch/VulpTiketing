import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ui/bento_aviso.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/ui/bento_falla.dart';
import '../../sync/sync_notifier.dart';
import '../categoria_model.dart';
import '../categoria_notifier.dart';
import '../producto_model.dart';
import '../producto_notifier.dart';
import 'banco_imagenes_dialog.dart';
import 'imagen_del_banco_vista.dart';

const _uuid = Uuid();

/// Formulario de crear/editar Producto — Ventana 3
/// (docs/pantallas/flujo-descripcion.md#ventana-3--crud-de-producto).
///
/// **La imagen se elige acá y solo acá**: es gestión de inventario. En las
/// pantallas de venta no hay foto — se probó al diseñarlas y una por tarjeta
/// dejaba el nombre y el precio, que es lo que se lee al cobrar, sin sitio.
///
/// Se elige del **banco** (decisión 0033): figuras de fábrica que no pesan, más
/// las fotos que se hayan sumado desde la galería o la cámara. El banco **no
/// viaja** en el backup ni en la sincronización, así que un producto cuya foto
/// no está en este aparato se ve con su figura propia — lo mismo que uno que
/// nunca eligió imagen. Nada se rompe y nada miente.
class ProductoFormDialog extends ConsumerStatefulWidget {
  const ProductoFormDialog({super.key, this.producto});

  /// Null = crear. No-null = editar.
  final Producto? producto;

  @override
  ConsumerState<ProductoFormDialog> createState() => _ProductoFormDialogState();
}

class _ProductoFormDialogState extends ConsumerState<ProductoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _precioController;
  String? _categoriaId;
  bool _guardando = false;

  /// La referencia elegida, tal como irá a `producto.imagen`.
  String? _imagen;

  bool get _esEdicion => widget.producto != null;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.producto?.nombre ?? '');
    _precioController = TextEditingController(
      text: widget.producto?.precioBase.toStringAsFixed(2) ?? '',
    );
    _categoriaId = widget.producto?.categoriaId;
    _imagen = widget.producto?.imagen;
  }

  Future<void> _elegirImagen() async {
    final elegida = await elegirDelBanco(context, semillaProducto: widget.producto?.id ?? 'nuevo');
    // `null` es cancelar y no cambia nada; `''` es "sin imagen", que sí es una
    // elección: devuelve al producto su figura propia.
    if (elegida == null || !mounted) return;
    setState(() => _imagen = elegida.isEmpty ? null : elegida);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  /// Devuelve el producto a la carta y cierra: lo que se quería hacer ya está
  /// hecho, y dejar el formulario abierto invitaría a un "Guardar" que no
  /// agrega nada.
  Future<void> _reactivar() async {
    setState(() => _guardando = true);
    await ref.read(productoNotifierProvider.notifier).recontinuar(widget.producto!.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// Borrado FÍSICO, con las tres condiciones de la decisión 0015 — de ahí que
  /// el resultado pueda ser un "no se puede" y no un simple ok.
  ///
  /// El gate de sincronización llega como parámetro y no se lee acá adentro,
  /// para no acoplar el formulario a SyncNotifier (0019).
  Future<void> _eliminar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('¿Eliminar el producto?'),
        contenido: Text(
          '"${widget.producto!.nombre}" se borra de verdad, no se puede deshacer. '
          'Si tuvo ventas alguna vez, no se va a poder: su historial lo necesita.',
        ),
        acciones: BentoAcciones(
          izquierda: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Eliminar'),
            ),
          ],
          derecha: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    final sincronizado = await ref.read(dispositivoSinParesProvider.future);
    if (!mounted) return;
    final resultado = await ref
        .read(productoNotifierProvider.notifier)
        .purgar(widget.producto!.id, todosLosDispositivosSincronizados: sincronizado);
    if (!mounted) return;

    setState(() => _guardando = false);
    switch (resultado) {
      case PurgarResultado.ok:
        Navigator.of(context).pop();
      case PurgarResultado.tieneVentasAsociadas:
        mostrarAviso(context, '✗ Tiene ventas: no se puede borrar');
      case PurgarResultado.faltaSincronizar:
        mostrarAviso(context, '✗ Falta sincronizar los otros aparatos');
    }
  }

  Future<void> _crearCategoria() async {
    final controller = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('Nueva categoría'),
        contenido: TextField(controller: controller, autofocus: true),
        acciones: BentoAcciones(
          izquierda: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Crear'),
            ),
          ],
          derecha: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    if (nombre == null || nombre.isEmpty || !mounted) return;

    final categoria = Categoria(id: _uuid.v4(), nombre: nombre, updatedAt: DateTime.now());
    await ref.read(categoriaNotifierProvider.notifier).crear(categoria);
    if (mounted) setState(() => _categoriaId = categoria.id);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final ahora = DateTime.now();
    final notifier = ref.read(productoNotifierProvider.notifier);
    final precio = double.parse(_precioController.text);

    if (_esEdicion) {
      await notifier.actualizar(
        Producto(
          id: widget.producto!.id,
          nombre: _nombreController.text.trim(),
          imagen: _imagen,
          categoriaId: _categoriaId,
          precioBase: precio,
          updatedAt: ahora,
          // Preserva deletedAt tal cual estaba — editar un producto NO debe
          // reactivar uno descontinuado por accidente (no existe una acción
          // explícita de "reactivar" todavía, esto habría sido una puerta
          // trasera silenciosa para hacerlo).
          deletedAt: widget.producto!.deletedAt,
        ),
      );
    } else {
      await notifier.crear(
        Producto(
          id: _uuid.v4(),
          nombre: _nombreController.text.trim(),
          imagen: _imagen,
          categoriaId: _categoriaId,
          precioBase: precio,
          updatedAt: ahora,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriaNotifierProvider);

    final formulario = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlDeImagen(
            // Sin elegir nada se ve la MISMA figura que va a verse en el
            // catálogo, no un cuadro vacío: así se sabe de antemano cómo va a
            // quedar el producto en la lista, y elegir imagen pasa a ser una
            // decisión en vez de un hueco por llenar.
            semilla: widget.producto?.id ?? 'nuevo',
            imagen: _imagen,
            ocupado: _guardando,
            onElegir: _elegirImagen,
          ),
          const SizedBox(height: BentoSpacing.unidad),
          TextFormField(
            controller: _nombreController,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          // Los campos con contorno necesitan aire entre sí: la etiqueta
          // flotante se dibuja SOBRE el borde superior, y pegados, "Precio
          // base" caía encima de la línea de abajo del campo Nombre.
          const SizedBox(height: BentoSpacing.unidad),
          TextFormField(
            controller: _precioController,
            decoration: const InputDecoration(labelText: 'Precio base (₡)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Requerido';
              if (double.tryParse(v) == null) return 'Número inválido';
              return null;
            },
          ),
          const SizedBox(height: BentoSpacing.unidad),
          categoriasAsync.when(
            data: (categorias) {
              // El producto puede apuntar a una categoría que ya no está —
              // pasa tras importar un catálogo con reemplazo, o cuando la
              // sincronización trae un borrado. Sin esta entrada extra, el
              // `DropdownButton` REVIENTA la pantalla entera con un assert
              // ("exactly one item with value X"), y editar el producto para
              // arreglarlo se vuelve imposible: justo lo que hace falta.
              //
              // Se muestra en vez de caer a "Sin categoría" en silencio: que
              // el dato esté roto tiene que verse, y elegir otra categoría lo
              // corrige al guardar.
              final huerfana = _categoriaId != null && !categorias.any((c) => c.id == _categoriaId);
              return Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _categoriaId,
                      // El desplegable ocupa el ancho que le den y recorta lo
                      // que sobre. Sin esto se dimensiona por su etiqueta más
                      // larga y se sale de la caja: "(categoría eliminada)"
                      // ya desbordaba 4,4 px, y un nombre de categoría largo
                      // haría lo mismo.
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      // Con elipsis, no cortado en seco: `isExpanded` recorta
                      // por el ancho disponible y sin esto un nombre largo
                      // termina a mitad de palabra, sin señal de que sigue.
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Sin categoría', overflow: TextOverflow.ellipsis),
                        ),
                        for (final c in categorias)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nombre, overflow: TextOverflow.ellipsis),
                          ),
                        if (huerfana)
                          DropdownMenuItem(
                            value: _categoriaId,
                            child: const Text(
                              'Categoría eliminada',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoriaId = v),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Nueva categoría',
                    onPressed: _crearCategoria,
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (e, st) => BentoFalla(
              mensaje: 'No se pudieron cargar las categorías.',
              error: e,
              onReintentar: () => ref.invalidate(categoriaNotifierProvider),
            ),
          ),
        ],
      ),
    );

    final acciones = BentoAcciones(
      izquierda: _esEdicion && !widget.producto!.activo
          ? [
              TextButton(onPressed: _guardando ? null : _reactivar, child: const Text('Reactivar')),
              TextButton(onPressed: _guardando ? null : _eliminar, child: const Text('Eliminar')),
            ]
          : const [],
      derecha: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );

    return BentoDialogo(
      titulo: Text(_esEdicion ? 'Editar producto' : 'Nuevo producto'),
      contenido: formulario,
      acciones: acciones,
    );
  }
}

/// La imagen del producto en el formulario: vista previa y "elegir del banco".
class _ControlDeImagen extends StatelessWidget {
  const _ControlDeImagen({
    required this.semilla,
    required this.imagen,
    required this.ocupado,
    required this.onElegir,
  });

  final String semilla;
  final String? imagen;
  final bool ocupado;
  final VoidCallback onElegir;

  /// Cuánto ocupa la vista previa. Un cuadro y no una franja ancha: es lo que se
  /// va a ver en la lista, y mostrarlo con otra forma prometería algo que
  /// después no se cumple.
  static const _lado = 72.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _lado,
          height: _lado,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BentoRadius.pozo),
            child: ImagenDelBancoVista(referencia: imagen, semillaPorDefecto: semilla),
          ),
        ),
        const SizedBox(width: BentoSpacing.gapCelda),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: ocupado ? null : onElegir,
              icon: const Icon(Icons.image_outlined),
              label: Text(imagen == null ? 'Elegir imagen' : 'Cambiar imagen'),
            ),
          ),
        ),
      ],
    );
  }
}
