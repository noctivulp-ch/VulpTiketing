import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configuracion/preferencias_notifier.dart';
import 'producto_model.dart';
import 'producto_notifier.dart';

/// Termino de busqueda de la pantalla activa — estado local de UI, no de
/// negocio (no vive en SQLite ni en preferencias persistidas).
final productoBusquedaProvider = StateProvider<String>((ref) => '');

/// Provider derivado, no un Notifier con estado propio (decision 0019):
/// combina la lista base de ProductoNotifier + el orden de
/// PreferenciasNotifier + el termino de busqueda, sin mutar nada.
///
/// TODO(0018): el ranking "nombre > categoria" con tolerancia a errores
/// ortograficos queda pendiente — placeholder de substring exacto por
/// nombre mientras tanto. No bloquea el resto del scaffold.
final productoQueryProvider = Provider<AsyncValue<List<Producto>>>((ref) {
  final productosAsync = ref.watch(productoNotifierProvider);
  final ordenAsync = ref.watch(preferenciasNotifierProvider);
  final termino = ref.watch(productoBusquedaProvider).trim().toLowerCase();

  return productosAsync.whenData((productos) {
    final orden = ordenAsync.valueOrNull ?? OrdenProducto.alfabetico;

    var lista = List<Producto>.from(productos);
    if (termino.isNotEmpty) {
      lista = lista
          .where((p) => p.nombre.toLowerCase().contains(termino))
          .toList();
    }

    switch (orden) {
      case OrdenProducto.alfabetico:
        lista.sort((a, b) => a.nombre.compareTo(b.nombre));
      case OrdenProducto.precio:
        lista.sort((a, b) => a.precioBase.compareTo(b.precioBase));
      case OrdenProducto.categoria:
        lista.sort(
          (a, b) => (a.categoriaId ?? '').compareTo(b.categoriaId ?? ''),
        );
    }
    return lista;
  });
});
