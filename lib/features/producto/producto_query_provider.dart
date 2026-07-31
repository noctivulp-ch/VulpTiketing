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
final productoQueryProvider = _query(incluirDescontinuados: false);

/// La misma lista, pero con los descontinuados dentro. La usa el catálogo del
/// Gerente.
///
/// Descontinuar es reversible (0005), así que el producto tiene que seguir
/// VIÉNDOSE en la pantalla desde la que se lo puede recontinuar. Antes
/// desaparecía de todos lados y la única salida era crearlo de nuevo con otro
/// id, partiendo su historial de ventas.
///
/// En las pantallas de venta no aparece: no se cobra algo que se sacó de la
/// carta.
final productoCatalogoProvider = _query(incluirDescontinuados: true);

Provider<AsyncValue<List<Producto>>> _query({required bool incluirDescontinuados}) {
  return Provider<AsyncValue<List<Producto>>>((ref) {
    final productosAsync = ref.watch(productoNotifierProvider);
    final ordenAsync = ref.watch(preferenciasNotifierProvider);
    final termino = ref.watch(productoBusquedaProvider).trim().toLowerCase();

    return productosAsync.whenData((productos) {
      final orden = ordenAsync.valueOrNull?.ordenProducto ?? OrdenProducto.alfabetico;

      var lista = List<Producto>.from(productos);
      if (!incluirDescontinuados) {
        lista = lista.where((p) => p.activo).toList();
      }
      if (termino.isNotEmpty) {
        lista = lista.where((p) => p.nombre.toLowerCase().contains(termino)).toList();
      }

      switch (orden) {
        case OrdenProducto.alfabetico:
          lista.sort((a, b) => a.nombre.compareTo(b.nombre));
        case OrdenProducto.precio:
          lista.sort((a, b) => a.precioBase.compareTo(b.precioBase));
        case OrdenProducto.categoria:
          lista.sort((a, b) => (a.categoriaId ?? '').compareTo(b.categoriaId ?? ''));
      }
      return lista;
    });
  });
}
