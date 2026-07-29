import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/sesion_notifier.dart';
import '../../sync/sync_notifier.dart';
import '../producto_model.dart';
import '../producto_notifier.dart';
import '../producto_query_provider.dart';
import 'producto_form_dialog.dart';

/// Ventana 3 — ver docs/pantallas/flujo-descripcion.md#ventana-3--crud-de-producto
/// y docs/pantallas/prototipos-ascii.md.
///
/// Permisos por rol (Operations.feature): Gerente ve Crear/Editar/
/// Descontinuar/Purgar; Registradora solo Editar.
class ProductoCrudScreen extends ConsumerWidget {
  const ProductoCrudScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productosAsync = ref.watch(productoQueryProvider);
    final sincronizado =
        ref.watch(syncNotifierProvider.notifier).todosLosDispositivosSincronizados;
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

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
            : ListView.builder(
                itemCount: productos.length,
                itemBuilder: (context, i) {
                  final producto = productos[i];
                  return ListTile(
                    title: Text(producto.nombre),
                    subtitle: Text(
                      producto.activo
                          ? '₡${producto.precioBase.toStringAsFixed(2)}'
                          : '₡${producto.precioBase.toStringAsFixed(2)} — descontinuado',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => ProductoFormDialog(producto: producto),
                          ),
                        ),
                        if (esGerente) ...[
                          if (producto.activo)
                            IconButton(
                              icon: const Icon(Icons.block),
                              tooltip: 'Descontinuar',
                              onPressed: () => ref
                                  .read(productoNotifierProvider.notifier)
                                  .descontinuar(producto.id),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever_outlined),
                            tooltip: sincronizado
                                ? 'Purgar'
                                : 'Purgar (requiere que todos los dispositivos estén sincronizados)',
                            onPressed: () => _confirmarYPurgar(
                              context,
                              ref,
                              producto,
                              sincronizado: sincronizado,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: esGerente
          ? FloatingActionButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ProductoFormDialog(),
              ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  /// Purgar es irreversible (0015) — SIEMPRE pide confirmación aparte,
  /// nunca borra al primer tap (ver docs/pantallas/prototipos-ascii.md).
  Future<void> _confirmarYPurgar(
    BuildContext context,
    WidgetRef ref,
    Producto producto, {
    required bool sincronizado,
  }) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Purgar este producto?'),
        content: Text(
          'Esto borra "${producto.nombre}" de forma permanente. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Purgar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;

    final resultado = await ref.read(productoNotifierProvider.notifier).purgar(
          producto.id,
          todosLosDispositivosSincronizados: sincronizado,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensaje(resultado))),
      );
    }
  }

  String _mensaje(PurgarResultado resultado) {
    switch (resultado) {
      case PurgarResultado.ok:
        return 'Producto purgado';
      case PurgarResultado.tieneVentasAsociadas:
        return 'No se puede purgar: tiene ventas asociadas';
      case PurgarResultado.faltaSincronizar:
        return 'No se puede purgar: faltan dispositivos por sincronizar';
    }
  }
}
