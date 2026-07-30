import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_corner_notice.dart';
import '../../../core/theme/bento_theme.dart';
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
      body: Column(
        children: [
          // Cascada invertida (mismo patron que el panel lateral de Ventana
          // 2): el buscador vive en la barra inferior, la lista crece hacia
          // arriba desde ahi con `reverse: true`.
          Expanded(
            child: productosAsync.when(
              data: (productos) => productos.isEmpty
                  ? const Center(child: Text('Sin productos'))
                  : ListView.separated(
                      reverse: true,
                      padding: const EdgeInsets.all(BentoSpacing.gapCelda),
                      itemCount: productos.length,
                      separatorBuilder: (_, _) => const SizedBox(height: BentoSpacing.unidad),
                      itemBuilder: (context, i) {
                        final producto = productos[i];
                        return _FilaProducto(
                          producto: producto,
                          esGerente: esGerente,
                          sincronizado: sincronizado,
                          onEditar: () => _editar(context, producto),
                          onDescontinuar: () async {
                            await ref
                                .read(productoNotifierProvider.notifier)
                                .descontinuar(producto.id);
                            if (context.mounted) {
                              mostrarNotificacionEsquina(context, '✓ Producto descontinuado');
                            }
                          },
                          onPurgar: () =>
                              _confirmarYPurgar(context, ref, producto, sincronizado: sincronizado),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
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
      mostrarNotificacionEsquina(context, '✓ Producto actualizado');
    }
  }

  Future<void> _crear(BuildContext context) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => const ProductoFormDialog(),
    );
    if (guardado == true && context.mounted) {
      mostrarNotificacionEsquina(context, '✓ Producto creado');
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
      mostrarNotificacionEsquina(context, _mensaje(resultado));
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
            child: const Icon(Icons.image_outlined, size: 22),
          ),
          const SizedBox(width: BentoSpacing.unidad),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(producto.nombre, style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  producto.activo
                      ? '₡${producto.precioBase.toStringAsFixed(2)}'
                      : '₡${producto.precioBase.toStringAsFixed(2)} — descontinuado',
                  style: Theme.of(context).textTheme.bodySmall,
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
