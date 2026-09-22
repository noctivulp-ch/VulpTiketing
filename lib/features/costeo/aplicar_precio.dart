import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../producto/producto_model.dart';
import '../producto/producto_notifier.dart';
import 'costeo_provider.dart';

/// Copia un precio al catálogo: al `precio_base` del producto, o al precio de
/// la variante (y al base si es la por defecto, que van en sincronía).
///
/// Es la ÚNICA puerta por la que el costeo escribe en el catálogo, y solo se
/// cruza con un botón explícito por artículo (0040 §4). Nunca en bloque.
///
/// Se parte del producto ACTUAL de la base, no del que trae [articulo]: ese es
/// la foto con la que se pintó la pantalla, y si entre medias se aplicó un
/// precio a otra variante del mismo producto, escribir desde la foto lo
/// pisaría. La prueba lo encontró: aplicar a Grande y luego a Pequeño dejaba
/// a Grande como estaba antes.
Future<void> aplicarPrecio(Ref ref, ArticuloDelCatalogo articulo, double precio) async {
  final actuales = await ref.read(productoNotifierProvider.future);
  final p = actuales.where((x) => x.id == articulo.producto.id).firstOrNull ?? articulo.producto;
  final v = articulo.variante;
  final ahora = DateTime.now();
  final Producto actualizado;
  if (v == null) {
    actualizado = Producto(
      id: p.id,
      nombre: p.nombre,
      imagen: p.imagen,
      categoriaId: p.categoriaId,
      precioBase: precio,
      variantes: p.variantes,
      updatedAt: ahora,
      deletedAt: p.deletedAt,
    );
  } else {
    final variantes = [for (final x in p.variantes) x.id == v.id ? x.copyWith(precio: precio) : x];
    final esPorDefecto = p.variantePorDefecto?.id == v.id;
    actualizado = Producto(
      id: p.id,
      nombre: p.nombre,
      imagen: p.imagen,
      categoriaId: p.categoriaId,
      precioBase: esPorDefecto ? precio : p.precioBase,
      variantes: variantes,
      updatedAt: ahora,
      deletedAt: p.deletedAt,
    );
  }
  await ref.read(productoNotifierProvider.notifier).actualizar(actualizado);
}

/// Para llamarlo desde una pantalla, que tiene `WidgetRef` y no `Ref`.
final aplicarPrecioProvider = Provider<Future<void> Function(ArticuloDelCatalogo, double)>(
  (ref) => (articulo, precio) => aplicarPrecio(ref, articulo, precio),
);
