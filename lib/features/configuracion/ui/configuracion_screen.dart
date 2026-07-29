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
/// conectados de verdad. Grid deslizante de tiles (boceto en
/// prototipos-ascii.md#ventana-5--configuración): agregar una opción nueva
/// a futuro es una celda más, el grid nunca se satura porque hace scroll
/// vertical — mismo principio que el rail de navegación del Dashboard.
class ConfiguracionScreen extends ConsumerWidget {
  const ConfiguracionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferenciasAsync = ref.watch(preferenciasNotifierProvider);
    final esGerente = ref.watch(sesionNotifierProvider) == Rol.gerente;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(BentoSpacing.gapCelda),
        children: [
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: BentoSpacing.gapCelda,
              crossAxisSpacing: BentoSpacing.gapCelda,
              childAspectRatio: 1,
            ),
            children: [
              _TileConfiguracion(
                icono: Icons.lock_outline,
                etiqueta: 'Cambiar contraseña',
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const CambiarContrasenaDialog(),
                ),
              ),
              _TileConfiguracion(
                icono: Icons.save_outlined,
                etiqueta: 'Exportar backup',
                onTap: () => mostrarDialogoExportarTiketback(context, ref),
              ),
              if (esGerente)
                _TileConfiguracion(
                  icono: Icons.restore_outlined,
                  etiqueta: 'Restaurar backup',
                  onTap: () => mostrarDialogoRestaurarTiketback(context, ref),
                ),
              if (esGerente)
                _TileConfiguracion(
                  icono: Icons.folder_open_outlined,
                  etiqueta: 'Catálogo (.tiketdata)',
                  onTap: () => mostrarDialogoCatalogo(context, ref),
                ),
              const _TileEstadoSync(),
              _TileConfiguracion(
                icono: Icons.logout,
                etiqueta: 'Cerrar sesión',
                onTap: () => ref.read(sesionNotifierProvider.notifier).cerrarSesion(),
              ),
            ],
          ),
          const Divider(height: BentoSpacing.gapGrupo * 2),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BentoSpacing.unidad),
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
          const SizedBox(height: BentoSpacing.gapCelda),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BentoSpacing.unidad),
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

/// Tile generico del grid de Configuración: ícono grande + etiqueta corta,
/// tolera texto porque es una pantalla de uso raro (no compite con el
/// criterio "sin leer" de las pantallas de venta — ver prototipos-ascii.md).
class _TileConfiguracion extends StatelessWidget {
  const _TileConfiguracion({required this.icono, required this.etiqueta, required this.onTap});

  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BentoRadius.celda),
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 32),
              const SizedBox(height: BentoSpacing.unidad),
              Text(
                etiqueta,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
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
/// solo cuando cambia idle/syncing/error) — tocar el tile para apagar y
/// prender vuelve a leer el valor actual.
///
/// Mismo formato de tile que el resto (ícono + etiqueta corta) — el estado
/// on/off se lee del ícono (relleno vs contorno) y una segunda línea de
/// texto compacta, en vez de un Switch/subtítulo largo que no entra en una
/// celda del grid. Tocar el tile entero alterna el estado (reemplaza al
/// Switch, misma acción en un control más grande y fácil de tocar).
class _TileEstadoSync extends ConsumerWidget {
  const _TileEstadoSync();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(syncNotifierProvider);
    final notifier = ref.read(syncNotifierProvider.notifier);
    final activo = estado == EstadoSync.syncing;

    return Card(
      child: InkWell(
        onTap: () => activo ? notifier.detenerSync() : notifier.iniciarSync(),
        borderRadius: BorderRadius.circular(BentoRadius.celda),
        child: Padding(
          padding: const EdgeInsets.all(BentoSpacing.paddingCelda),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(activo ? Icons.wifi_tethering : Icons.wifi_tethering_off, size: 32),
              const SizedBox(height: BentoSpacing.unidad),
              Text(
                'Sincronización',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                activo ? '${notifier.paresVisibles.length} par(es)' : 'Detenida',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
