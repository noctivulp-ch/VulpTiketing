import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/theme/bento_cuadricula.dart';
import '../../../core/theme/bento_velo.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_falla.dart';
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
    // El catálogo del Gerente SÍ muestra los descontinuados: es la única
    // pantalla desde la que se puede recontinuarlos.
    final productosAsync = ref.watch(productoCatalogoProvider);
    final sincronizado = ref.watch(syncNotifierProvider.notifier).todosLosDispositivosSincronizados;
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

    return Scaffold(
      body: Column(
        children: [
          // Cascada invertida (mismo patron que el panel lateral de Ventana
          // 2): el buscador vive en la barra inferior, la lista crece hacia
          // arriba desde ahi con `reverse: true`.
          Expanded(
            child: productosAsync.when(
              data: (productos) => productos.isEmpty
                  ? const Center(child: Text('Sin productos'))
                  : GridView.builder(
                      // Se conserva la cascada invertida: la lista crece hacia
                      // arriba desde el buscador de la barra inferior.
                      reverse: true,
                      // El padding va en coordenadas de pantalla aunque el
                      // scroll este invertido: el velo esta arriba, o sea `top`.
                      padding: EdgeInsets.fromLTRB(
                        BentoSpacing.gapCelda,
                        bentoInsetSuperior(context),
                        BentoSpacing.gapCelda,
                        BentoSpacing.gapCelda,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        // Una fila de producto ocupa 6, 3 o 2 columnas: en
                        // teléfono va a lo ancho, en escritorio caben tres.
                        crossAxisCount: bentoPorFila(
                          BentoAncho.de(context),
                          compacto: 6,
                          medio: 3,
                          amplio: 2,
                        ),
                        mainAxisSpacing: BentoSpacing.pared,
                        crossAxisSpacing: BentoSpacing.pared,
                        // Alto fijo en vez de proporción: estas celdas son
                        // filas, y su alto lo fija el contenido (miniatura de
                        // 44 y botones de 48), no el ancho de la columna.
                        mainAxisExtent: 76,
                      ),
                      itemCount: productos.length,
                      itemBuilder: (context, i) {
                        final producto = productos[i];
                        return _FilaProducto(
                          producto: producto,
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Purgar este producto?'),
        content: Text('Esto borra "${producto.nombre}" de forma permanente. No se puede deshacer.'),
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
    required this.esGerente,
    required this.sincronizado,
    required this.onEditar,
    required this.onDescontinuar,
    required this.onPurgar,
  });

  final Producto producto;
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
          Container(
            width: bentoMiniatura,
            height: bentoMiniatura,
            decoration: BoxDecoration(
              color: lacaDe(context).pozoContacto,
              borderRadius: BorderRadius.circular(BentoRadius.pozo - BentoSpacing.unidad / 2),
            ),
            // La miniatura es la señal que se ve sin leer: un producto fuera
            // de la carta se distingue de un vistazo en una lista larga.
            child: Icon(
              producto.activo ? Icons.image_outlined : Icons.block,
              size: 22,
              color: producto.activo ? null : Theme.of(context).colorScheme.onSurfaceVariant,
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
                  producto.activo
                      ? '₡${producto.precioBase.toStringAsFixed(2)}'
                      : 'Fuera de la carta · ₡${producto.precioBase.toStringAsFixed(2)}',
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
