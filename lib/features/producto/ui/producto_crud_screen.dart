import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_fotos.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
import '../../auth/sesion_notifier.dart';
import '../../sync/sync_notifier.dart';
import '../producto_model.dart';
import '../producto_notifier.dart';
import '../producto_query_provider.dart';
import 'imagen_del_banco_vista.dart';
import 'lista_productos_agrupada.dart';
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
    // El catálogo del Gerente SÍ muestra los descontinuados: es la única
    // pantalla desde la que se puede recontinuarlos.
    final productosAsync = ref.watch(productoCatalogoAgrupadoProvider);
    // `false` mientras se lee: nunca habilitar un borrado físico por no haber
    // terminado de comprobar si hay otros aparatos.
    final sincronizado = ref.watch(dispositivoSinParesProvider).valueOrNull ?? false;
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;
    final categorias = ref.watch(nombresDeCategoriaProvider);

    return Scaffold(
      body: Column(
        children: [
          // Cascada invertida (mismo patron que el panel lateral de Ventana
          // 2): el buscador vive en la barra inferior, la lista crece hacia
          // arriba desde ahi con `reverse: true`.
          Expanded(
            child: productosAsync.when(
              data: (grupos) => grupos.every((g) => g.productos.isEmpty)
                  ? const Center(child: Text('Sin productos'))
                  : ListaProductosAgrupada(
                      grupos: grupos,
                      // Se conserva la cascada invertida: la lista crece hacia
                      // arriba desde el buscador de la barra inferior.
                      invertida: true,
                      // El padding va en coordenadas de pantalla aunque el
                      // scroll este invertido: el velo esta arriba, o sea `top`.
                      padding: EdgeInsets.fromLTRB(
                        BentoSpacing.gapCelda,
                        bentoInsetSuperior(context),
                        BentoSpacing.gapCelda,
                        BentoSpacing.gapCelda,
                      ),
                      // Una fila de producto ocupa 6, 3 o 2 columnas: en
                      // teléfono va a lo ancho, en escritorio caben tres.
                      porFila: bentoPorFila(
                        BentoAncho.de(context),
                        compacto: 6,
                        medio: 3,
                        amplio: 2,
                      ),
                      // Alto fijo en vez de proporción: estas celdas son filas,
                      // y su alto lo fija el contenido (miniatura de 44 y
                      // botones de 48), no el ancho de la columna.
                      altoCelda: 76,
                      celda: (producto) {
                        return _FilaProducto(
                          producto: producto,
                          categoria: categorias[producto.categoriaId],
                          esGerente: esGerente,
                          sincronizado: sincronizado,
                          onEditar: () => _editar(context, producto),
                          onDescontinuar: () async {
                            final notifier = ref.read(productoNotifierProvider.notifier);
                            if (producto.activo) {
                              await notifier.descontinuar(producto.id);
                            } else {
                              await notifier.recontinuar(producto.id);
                            }
                            if (context.mounted) {
                              mostrarAviso(
                                context,
                                producto.activo
                                    ? '✓ Producto descontinuado'
                                    : '✓ Producto de vuelta en la carta',
                              );
                            }
                          },
                          onPurgar: () =>
                              _confirmarYPurgar(context, ref, producto, sincronizado: sincronizado),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => BentoFalla(
                mensaje: 'No se pudo cargar el catálogo.',
                error: e,
                onReintentar: () => ref.invalidate(productoNotifierProvider),
              ),
            ),
          ),
          // Barra inferior unificada: buscador + agregar en el mismo panel
          // (antes el buscador vivia en el AppBar y "agregar" era un FAB
          // flotando aparte, sin relacion visual con el buscador).
          ColoredBox(
            color: lacaDe(context).pozo,
            child: SafeArea(
              top: false,
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
                    if (esGerente) ...[
                      const SizedBox(width: BentoSpacing.unidad),
                      FilledButton.icon(
                        onPressed: () => _crear(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Nuevo'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editar(BuildContext context, Producto producto) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => ProductoFormDialog(producto: producto),
    );
    if (guardado == true && context.mounted) {
      mostrarAviso(context, '✓ Producto actualizado');
    }
  }

  Future<void> _crear(BuildContext context) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => const ProductoFormDialog(),
    );
    if (guardado == true && context.mounted) {
      mostrarAviso(context, '✓ Producto creado');
    }
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
      builder: (dialogContext) => BentoDialogo(
        titulo: const Text('¿Purgar este producto?'),
        contenido: Text(
          'Esto borra "${producto.nombre}" de forma permanente. No se puede deshacer.',
        ),
        acciones: BentoAcciones(
          izquierda: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Purgar'),
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
    if (confirmado != true || !context.mounted) return;

    final resultado = await ref
        .read(productoNotifierProvider.notifier)
        .purgar(producto.id, todosLosDispositivosSincronizados: sincronizado);
    if (context.mounted) {
      mostrarAviso(context, _mensaje(resultado));
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

/// Mismo lenguaje visual que `_TarjetaProducto` (Ventana 1) y
/// `_FilaLineaVenta` (Ventana 2): placeholder cuadrado + nombre + precio,
/// en formato de fila — consistencia entre pantallas (skill
/// `aesthetic-usability`).
class _FilaProducto extends StatelessWidget {
  const _FilaProducto({
    required this.producto,
    required this.categoria,
    required this.esGerente,
    required this.sincronizado,
    required this.onEditar,
    required this.onDescontinuar,
    required this.onPurgar,
  });

  final Producto producto;

  /// El nombre de su categoría: de ahí sale la cara cuando nadie le eligió una.
  final String? categoria;

  final bool esGerente;
  final bool sincronizado;
  final VoidCallback onEditar;
  final VoidCallback onDescontinuar;
  final VoidCallback onPurgar;

  @override
  Widget build(BuildContext context) {
    return BentoPozo(
      padding: const EdgeInsets.all(BentoSpacing.unidad),
      child: Row(
        children: [
          // La miniatura es la señal que se ve sin leer: un producto fuera de
          // la carta se distingue de un vistazo en una lista larga.
          //
          // Aquí el hueco va SIEMPRE, con imagen o sin ella: es una lista de
          // filas de alto fijo, así que la miniatura no le quita sitio a nada.
          // En Venta Rápida y en el carrito es al revés — ahí el hueco se lo
          // disputa el nombre y solo aparece si hay imagen de verdad.
          SizedBox(
            width: bentoMiniatura,
            height: bentoMiniatura,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BentoRadius.pozo - BentoSpacing.unidad / 2),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImagenDelBancoVista(
                    referencia: producto.imagen,
                    ventana: VentanaConFotos.inventario,
                    categoria: categoria,
                    apagada: !producto.activo,
                  ),
                  // El aspa va en una ESQUINA y pequeña, no centrada y del
                  // mismo tamaño que lo de abajo. Centradas, las dos marcas se
                  // pisaban y no se leía ninguna: un cubierto y una prohibición
                  // superpuestos son un borrón, no dos datos.
                  //
                  // Y son dos datos distintos que hacen falta a la vez — qué es
                  // el producto y que está fuera de la carta—, así que la
                  // respuesta es apartarlas, no callar una.
                  if (!producto.activo)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        // Fondo propio: encima de una foto clara, el aspa sola
                        // desaparecía.
                        decoration: BoxDecoration(
                          color: lacaDe(context).pozo,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(BentoRadius.pozo / 2),
                          ),
                        ),
                        padding: const EdgeInsets.only(left: 2, top: 2),
                        child: Icon(
                          Icons.block,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: BentoSpacing.unidad),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // La celda tiene alto fijo (es una fila de una cuadrícula), así
                // que el nombre se corta en vez de envolver: dos líneas de un
                // nombre largo desbordarían la celda.
                Text(
                  producto.nombre,
                  style: Theme.of(context).textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  // El PRECIO primero: cuando el subtítulo no entra, la elipsis
                  // se come lo último. Con el estado delante, "Fuera de la
                  // carta · ₡15000" salía como "Fuera de la carta · ₡1500…" —
                  // un número recortado se lee como otro número, y eso es peor
                  // que no verlo.
                  producto.activo
                      ? '₡${producto.precioBase.toStringAsFixed(2)}'
                      : '₡${producto.precioBase.toStringAsFixed(2)} · Fuera de la carta',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    // Atenuado, no translúcido: bajar la opacidad se
                    // llevaría el contraste por debajo del mínimo AA, y el
                    // dato tiene que seguir leyéndose.
                    color: producto.activo ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: onEditar),
          if (esGerente) ...[
            if (producto.activo)
              IconButton(
                icon: const Icon(Icons.block),
                tooltip: 'Descontinuar',
                onPressed: onDescontinuar,
              ),
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: sincronizado
                  ? 'Purgar'
                  : 'Purgar (requiere que todos los dispositivos estén sincronizados)',
              onPressed: onPurgar,
            ),
          ],
        ],
      ),
    );
  }
}
