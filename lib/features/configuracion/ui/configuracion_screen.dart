import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';
import '../../import_export/ui/tiketback_dialogs.dart';
import '../../import_export/ui/tiketdata_dialogs.dart';
import '../../sync/sync_notifier.dart';
import '../preferencias_notifier.dart';
import 'cambiar_contrasena_dialog.dart';

/// Ventana 5 — ver docs/pantallas/flujo-descripcion.md#ventana-5--configuración.
/// Orden de productos, acento (decision 0018 / iconografia.md), cambiar
/// contraseña, exportar/restaurar backup (.tiketback) y cerrar sesión ya
/// conectados de verdad; el catálogo (.tiketdata) queda pendiente. TODO:
/// convertir a grid deslizante de tiles (boceto en prototipos-ascii.md) —
/// hoy es una ListView simple mientras se completan los servicios reales.
class ConfiguracionScreen extends ConsumerWidget {
  const ConfiguracionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferenciasAsync = ref.watch(preferenciasNotifierProvider);
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

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
          ListTile(
            leading: const Icon(Icons.save_outlined),
            title: const Text('Exportar backup (.tiketback)'),
            onTap: () => mostrarDialogoExportarTiketback(context, ref),
          ),
          if (esGerente)
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('Restaurar backup (.tiketback)'),
              onTap: () => mostrarDialogoRestaurarTiketback(context, ref),
            ),
          if (esGerente)
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Importar/exportar catálogo (.tiketdata)'),
              onTap: () => mostrarDialogoCatalogo(context, ref),
            ),
          const _TileEstadoSync(),
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

/// Descubrimiento (0021) y transporte (0022: servidor HTTP + cliente)
/// ya son reales — al activar el switch, este dispositivo publica su
/// servicio mDNS, levanta su servidor de sync y sincroniza con cada par
/// del mismo rol que descubre. Lo que falta es la coordinacion
/// *entre* grupos (Gerente ↔ Registradora vía orquestadores, 0007) — ver
/// nota en SyncNotifier.
///
/// Limitacion conocida: el contador de pares visibles no se refresca en
/// vivo (SyncNotifier no emite un nuevo `state` cuando cambian los pares,
/// solo cuando cambia idle/syncing/error) — apagar y prender el switch
/// vuelve a leer el valor actual.
class _TileEstadoSync extends ConsumerWidget {
  const _TileEstadoSync();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(syncNotifierProvider);
    final notifier = ref.read(syncNotifierProvider.notifier);
    final activo = estado == EstadoSync.syncing;

    return ListTile(
      leading: Icon(activo ? Icons.wifi_tethering : Icons.wifi_tethering_off),
      title: const Text('Sincronización (descubrimiento)'),
      subtitle: Text(
        activo
            ? '${notifier.paresVisibles.length} dispositivo(s) del mismo rol visibles'
                '${notifier.esOrquestadorDeMiGrupo ? " — este es el orquestador" : ""}'
            : 'Detenida — actívala para sincronizar con dispositivos del mismo rol',
      ),
      trailing: Switch(
        value: activo,
        onChanged: (v) => v ? notifier.iniciarSync() : notifier.detenerSync(),
      ),
    );
  }
}
