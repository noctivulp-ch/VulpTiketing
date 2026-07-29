import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';
import '../preferencias_notifier.dart';
import 'cambiar_contrasena_dialog.dart';

/// Ventana 5 — ver docs/pantallas/flujo-descripcion.md#ventana-5--configuración.
/// Orden de productos, acento (decision 0018 / iconografia.md), cambiar
/// contraseña y cerrar sesión ya conectados de verdad; el resto
/// (backup/.tiketback, catálogo/.tiketdata, estado de sync) queda pendiente
/// de esos servicios. TODO: convertir a grid deslizante de tiles (boceto en
/// prototipos-ascii.md) — hoy es una ListView simple mientras se completan
/// los servicios reales.
class ConfiguracionScreen extends ConsumerWidget {
  const ConfiguracionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferenciasAsync = ref.watch(preferenciasNotifierProvider);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Cambiar contraseña'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const CambiarContrasenaDialog(),
            ),
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
          preferenciasAsync.when(
            data: (prefs) => SegmentedButton<OrdenProducto>(
              segments: const [
                ButtonSegment(value: OrdenProducto.alfabetico, label: Text('Alfabético')),
                ButtonSegment(value: OrdenProducto.precio, label: Text('Precio')),
                ButtonSegment(value: OrdenProducto.categoria, label: Text('Categoría')),
              ],
              selected: {prefs.ordenProducto},
              onSelectionChanged: (seleccion) => ref
                  .read(preferenciasNotifierProvider.notifier)
                  .cambiarOrden(seleccion.first),
            ),
            loading: () => const CircularProgressIndicator(),
            error: (e, st) => Text('Error: $e'),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Acento', style: Theme.of(context).textTheme.titleMedium),
          ),
          preferenciasAsync.when(
            data: (prefs) => SegmentedButton<AcentoTinte>(
              segments: const [
                ButtonSegment(value: AcentoTinte.grisAzulado, label: Text('Azulado')),
                ButtonSegment(value: AcentoTinte.grisVerdoso, label: Text('Verdoso')),
                ButtonSegment(value: AcentoTinte.grisCafe, label: Text('Café')),
              ],
              selected: {prefs.acento},
              onSelectionChanged: (seleccion) => ref
                  .read(preferenciasNotifierProvider.notifier)
                  .cambiarAcento(seleccion.first),
            ),
            loading: () => const SizedBox.shrink(),
            error: (e, st) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
