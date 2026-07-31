import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../carpeta_exportacion.dart';

/// Muestra dónde exporta la app y deja cambiarlo.
///
/// La carpeta se elige UNA vez y vale para backups, catálogos y reportes.
/// Antes cada exportación abría el selector del sistema — un paso de más
/// siempre, y en Android encima roto: `saveFile` exige los bytes del archivo
/// por adelantado, y un backup puede pesar más que la memoria libre.
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
    // Se comprueba escribiendo de verdad: en Android una carpeta compartida por
    // SAF llega como `content://` y `dart:io` no sabe abrirla. Descubrirlo al
    // exportar un backup sería tarde.
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
    final carpeta = ref.watch(carpetaExportacionProvider);
    final textos = Theme.of(context).textTheme;

    return BentoPozo(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Se guarda en', style: textos.labelLarge),
          const SizedBox(height: BentoSpacing.unidad / 2),
          Text(
            carpeta.valueOrNull?.path ?? 'Resolviendo…',
            style: textos.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
      ),
    );
  }
}
