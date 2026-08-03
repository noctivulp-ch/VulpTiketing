import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../configuracion/preferencias_notifier.dart';
import 'categoria_notifier.dart';
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

/// Etiqueta de la categoría a la que no pertenece nadie. Va al final de la
/// lista: es un cajón de sastre, no una categoría más.
const sinCategoria = 'Sin categoría';

Provider<AsyncValue<List<Producto>>> _query({required bool incluirDescontinuados}) {
  return Provider<AsyncValue<List<Producto>>>((ref) {
    final productosAsync = ref.watch(productoNotifierProvider);
    final ordenAsync = ref.watch(preferenciasNotifierProvider);
    final termino = ref.watch(productoBusquedaProvider).trim().toLowerCase();
    final nombres = ref.watch(nombresDeCategoriaProvider);

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
          // Por NOMBRE de categoría, no por su id. Ordenar por el id ordenaba
          // por UUID: el resultado era un orden arbitrario que cambiaba en cada
          // aparato y que además no se parecía en nada a lo que el ajuste
          // promete. Dentro de cada categoría, alfabético.
          lista.sort((a, b) {
            final ca = _clave(nombres, a.categoriaId);
            final cb = _clave(nombres, b.categoriaId);
            final porCategoria = ca.compareTo(cb);
            return porCategoria != 0 ? porCategoria : a.nombre.compareTo(b.nombre);
          });
      }
      return lista;
    });
  });
}

/// El nombre de la categoría, con las huérfanas al final.
///
/// El `\uffff` empuja "Sin categoría" detrás de cualquier nombre real sin
/// tratarlo como caso aparte en el `sort`.
String _clave(Map<String, String> nombres, String? categoriaId) {
  final nombre = categoriaId == null ? null : nombres[categoriaId];
  return nombre == null ? '\uffff' : nombre.toLowerCase();
}

/// Id de categoría → nombre, para no repetir el cruce en cada pantalla.
final nombresDeCategoriaProvider = Provider<Map<String, String>>((ref) {
  final categorias = ref.watch(categoriaNotifierProvider).valueOrNull ?? const [];
  return {for (final c in categorias) c.id: c.nombre};
});

/// Un tramo de la lista de productos con su título.
///
/// Existe porque el ajuste "ordenar por categoría" agrupaba sin decir por dónde
/// empezaba cada grupo: se veían los productos en un orden que no se explicaba
/// solo. Con los otros dos órdenes hay un único grupo sin título — el orden se
/// lee del propio contenido (alfabético, precio) y un encabezado sobraría.
class GrupoDeProductos {
  const GrupoDeProductos({required this.titulo, required this.productos});

  /// `null` cuando el orden no agrupa.
  final String? titulo;
  final List<Producto> productos;
}

Provider<AsyncValue<List<GrupoDeProductos>>> _agrupado(
  Provider<AsyncValue<List<Producto>>> fuente,
) {
  return Provider<AsyncValue<List<GrupoDeProductos>>>((ref) {
    final orden =
        ref.watch(preferenciasNotifierProvider).valueOrNull?.ordenProducto ??
        OrdenProducto.alfabetico;
    final nombres = ref.watch(nombresDeCategoriaProvider);

    return ref.watch(fuente).whenData((productos) {
      if (orden != OrdenProducto.categoria) {
        return [GrupoDeProductos(titulo: null, productos: productos)];
      }
      final grupos = <GrupoDeProductos>[];
      for (final producto in productos) {
        final titulo = nombres[producto.categoriaId] ?? sinCategoria;
        if (grupos.isEmpty || grupos.last.titulo != titulo) {
          grupos.add(GrupoDeProductos(titulo: titulo, productos: []));
        }
        grupos.last.productos.add(producto);
      }
      return grupos;
    });
  });
}

/// La lista de venta, agrupada por categoría cuando ese es el orden elegido.
final productoAgrupadoProvider = _agrupado(productoQueryProvider);

/// La misma agrupación para el catálogo del Gerente, descontinuados incluidos.
final productoCatalogoAgrupadoProvider = _agrupado(productoCatalogoProvider);
