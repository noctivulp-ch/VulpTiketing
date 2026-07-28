import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/sync_notifier.dart';
import '../producto_notifier.dart';
import '../producto_query_provider.dart';

/// Ventana 3 — ver docs/pantallas/flujo-descripcion.md#ventana-3--crud-de-producto
/// y docs/pantallas/prototipos-ascii.md. Gerente-only: crear/descontinuar/purgar
/// (permisos reales quedan pendientes de wiring con SesionNotifier — placeholder
/// muestra todas las acciones por ahora).
class ProductoCrudScreen extends ConsumerWidget {
  const ProductoCrudScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productosAsync = ref.watch(productoQueryProvider);
    final sincronizado = ref.watch(syncNotifierProvider.notifier).todosLosDispositivosSincronizados;

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
        data: (productos) => ListView.builder(
          itemCount: productos.length,
          itemBuilder: (context, i) {
            final producto = productos[i];
            return ListTile(
              title: Text(producto.nombre),
              subtitle: Text('₡${producto.precioBase.toStringAsFixed(2)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {}, // TODO: formulario de edicion
                  ),
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
                    onPressed: () async {
                      final resultado = await ref
                          .read(productoNotifierProvider.notifier)
                          .purgar(
                            producto.id,
                            todosLosDispositivosSincronizados: sincronizado,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_mensaje(resultado))),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {}, // TODO: formulario de creacion (Gerente-only)
        child: const Icon(Icons.add),
      ),
    );
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
