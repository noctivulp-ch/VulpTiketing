import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/bento_corner_notice.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
import '../../sync/sync_notifier.dart';
import '../categoria_model.dart';
import '../categoria_notifier.dart';
import '../producto_model.dart';
import '../producto_notifier.dart';

const _uuid = Uuid();

/// Formulario de crear/editar Producto — Ventana 3
/// (docs/pantallas/flujo-descripcion.md#ventana-3--crud-de-producto).
///
/// La imagen queda fuera de este formulario a propósito: sincronizar el
/// archivo de imagen entre dispositivos (no solo la ruta guardada en
/// `producto.imagen`) es una pregunta de arquitectura sin resolver todavía
/// — agregar un selector de imagen ahora resolvería solo la mitad del
/// problema y dejaría una promesa rota (foto elegida que nunca llega al
/// otro dispositivo). Se deja anotado como pendiente real, no un olvido.
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

  bool get _esEdicion => widget.producto != null;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(text: widget.producto?.nombre ?? '');
    _precioController = TextEditingController(
      text: widget.producto?.precioBase.toStringAsFixed(2) ?? '',
    );
    _categoriaId = widget.producto?.categoriaId;
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar el producto?'),
        content: Text(
          '"${widget.producto!.nombre}" se borra de verdad, no se puede deshacer. '
          'Si tuvo ventas alguna vez, no se va a poder: su historial lo necesita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    final sincronizado = ref.read(syncNotifierProvider.notifier).todosLosDispositivosSincronizados;
    final resultado = await ref
        .read(productoNotifierProvider.notifier)
        .purgar(widget.producto!.id, todosLosDispositivosSincronizados: sincronizado);
    if (!mounted) return;

    setState(() => _guardando = false);
    switch (resultado) {
      case PurgarResultado.ok:
        Navigator.of(context).pop();
      case PurgarResultado.tieneVentasAsociadas:
        mostrarNotificacionEsquina(context, '✗ Tiene ventas: no se puede borrar');
      case PurgarResultado.faltaSincronizar:
        mostrarNotificacionEsquina(context, '✗ Falta sincronizar los otros aparatos');
    }
  }

  Future<void> _crearCategoria() async {
    final controller = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
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
          imagen: widget.producto!.imagen,
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

    return AlertDialog(
      title: Text(_esEdicion ? 'Editar producto' : 'Nuevo producto'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                final huerfana =
                    _categoriaId != null && !categorias.any((c) => c.id == _categoriaId);
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
      ),
      // Cuadrícula, no una fila que se apila sola: con cuatro acciones el
      // `AlertDialog` las pone una debajo de otra en cuanto no caben, y cuatro
      // botones en columna se leen como una lista de opciones, no como las
      // salidas del formulario.
      //
      // Dos columnas con significados distintos: a la izquierda lo que le pasa
      // AL PRODUCTO (volver a la carta, borrarlo), a la derecha lo que le pasa
      // A ESTE FORMULARIO (salir, guardar).
      actions: [
        _Acciones(
          alProducto: _esEdicion && !widget.producto!.activo
              ? [
                  TextButton(
                    onPressed: _guardando ? null : _reactivar,
                    child: const Text('Reactivar'),
                  ),
                  TextButton(
                    onPressed: _guardando ? null : _eliminar,
                    child: const Text('Eliminar'),
                  ),
                ]
              : const [],
          alFormulario: [
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
        ),
      ],
    );
  }
}

/// Las acciones del formulario en dos columnas: producto a la izquierda,
/// formulario a la derecha.
///
/// Fila por fila y no una `Row` con los cuatro: en 360 dp no entran de ancho, y
/// dejar que el diálogo los apile solo los alinea a todos a la derecha —
/// perdiendo justamente la distinción entre las dos columnas.
class _Acciones extends StatelessWidget {
  const _Acciones({required this.alProducto, required this.alFormulario});

  /// Lo que le pasa al producto. Vacío cuando está en la carta: no hay nada que
  /// reactivar ni conviene ofrecer borrar algo que se está usando.
  final List<Widget> alProducto;

  /// Lo que le pasa a este formulario. Siempre hay dos: salir y guardar.
  final List<Widget> alFormulario;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < alFormulario.length; i++)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (i < alProducto.length) alProducto[i] else const SizedBox.shrink(),
              alFormulario[i],
            ],
          ),
      ],
    );
  }
}
