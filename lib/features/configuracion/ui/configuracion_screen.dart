import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/sesion_notifier.dart';
import '../preferencias_notifier.dart';

/// Ventana 5 — ver docs/pantallas/flujo-descripcion.md#ventana-5--configuración.
/// Orden de productos (decision 0018) y cerrar sesion ya conectados de
/// verdad; el resto (cambiar contraseña, backup/.tiketback,
/// catálogo/.tiketdata, estado de sync) queda pendiente de esos servicios.
class ConfiguracionScreen extends ConsumerWidget {
  const ConfiguracionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordenAsync = ref.watch(preferenciasNotifierProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Cambiar contraseña'),
            subtitle: Text('Pendiente (CredencialesService)'),
          ),
          const ListTile(
            leading: Icon(Icons.save_outlined),
            title: Text('Exportar backup (.tiketback)'),
            subtitle: Text('Pendiente (TiketbackNotifier)'),
          ),
          const ListTile(
            leading: Icon(Icons.folder_open_outlined),
            title: Text('Importar/exportar catálogo (.tiketdata)'),
            subtitle: Text('Pendiente (TiketdataNotifier)'),
          ),
          const ListTile(
            leading: Icon(Icons.wifi_tethering),
            title: Text('Estado de sincronización'),
            subtitle: Text('Pendiente (SyncNotifier)'),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: () => ref.read(sesionNotifierProvider.notifier).cerrarSesion(),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Orden de productos', style: Theme.of(context).textTheme.titleMedium),
          ),
          ordenAsync.when(
            data: (orden) => SegmentedButton<OrdenProducto>(
              segments: const [
                ButtonSegment(value: OrdenProducto.alfabetico, label: Text('Alfabético')),
                ButtonSegment(value: OrdenProducto.precio, label: Text('Precio')),
                ButtonSegment(value: OrdenProducto.categoria, label: Text('Categoría')),
              ],
              selected: {orden},
              onSelectionChanged: (seleccion) => ref
                  .read(preferenciasNotifierProvider.notifier)
                  .cambiarOrden(seleccion.first),
            ),
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
