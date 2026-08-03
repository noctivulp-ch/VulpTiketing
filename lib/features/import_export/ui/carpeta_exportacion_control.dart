import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../carpeta_exportacion.dart';

/// Dice dónde queda lo que la app exporta, y deja cambiarlo donde eso tenga
/// sentido.
///
/// En Android **no** se puede elegir: todo va a `Descargas/VulpTiketing` por
/// MediaStore, que es la única carpeta visible en la que la app puede escribir
/// sin pedir permisos. Ofrecer un selector ahí sería ofrecer algo que no
/// funciona — es lo que pasaba antes, con las exportaciones cayendo en
/// `Android/data/`, invisible salvo conectando el teléfono a una computadora.
///
/// En escritorio sí se elige, porque ahí `dart:io` escribe donde le digan.
class CarpetaExportacionControl extends ConsumerWidget {
  const CarpetaExportacionControl({super.key});

  Future<void> _cambiar(BuildContext context, WidgetRef ref) async {
    final elegida = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Elegir carpeta de exportación',
    );
    if (elegida == null || !context.mounted) return;

    final ok = await const CarpetaExportacion().cambiar(elegida);
    if (!context.mounted) return;

    ref.invalidate(carpetaExportacionProvider);
    // Se comprueba escribiendo de verdad: que una carpeta exista no implica que
    // la app pueda escribir en ella, y descubrirlo al exportar sería tarde.
    mostrarAviso(context, ok ? '✓ Carpeta cambiada' : '✗ No se puede escribir en esa carpeta');
  }

  Future<void> _restablecer(BuildContext context, WidgetRef ref) async {
    await const CarpetaExportacion().restablecer();
    if (!context.mounted) return;
    ref.invalidate(carpetaExportacionProvider);
    mostrarAviso(context, '✓ Carpeta por defecto');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textos = Theme.of(context).textTheme;
    final enAndroid = Platform.isAndroid;
    final carpeta = ref.watch(carpetaExportacionProvider);

    return BentoPozo(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Se guarda en', style: textos.labelLarge),
          const SizedBox(height: BentoSpacing.unidad / 2),
          Text(
            enAndroid ? 'Descargas › VulpTiketing' : carpeta.valueOrNull?.path ?? 'Resolviendo…',
            style: textos.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (enAndroid) ...[
            const SizedBox(height: BentoSpacing.unidad / 2),
            Text(
              'Backups, catálogos y reportes quedan ahí, con el gestor de '
              'archivos del teléfono.',
              style: textos.bodySmall?.copyWith(color: lacaDe(context).textoAtenuadoEnBandeja),
            ),
          ] else ...[
            const SizedBox(height: BentoSpacing.unidad),
            Wrap(
              spacing: BentoSpacing.unidad,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Cambiar'),
                  onPressed: () => _cambiar(context, ref),
                ),
                TextButton(
                  onPressed: () => _restablecer(context, ref),
                  child: const Text('Por defecto'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
