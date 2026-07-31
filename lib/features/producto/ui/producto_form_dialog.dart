import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
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
              data: (categorias) => Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _categoriaId,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Sin categoría')),
                        for (final c in categorias)
                          DropdownMenuItem(value: c.id, child: Text(c.nombre)),
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
              ),
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
      actions: [
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
  }
}
