import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tiketdata_notifier.dart';
import '../tiketdata_service.dart';

void _mostrarMensaje(BuildContext context, String? mensaje) {
  if (mensaje == null) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}

/// Punto de entrada — pregunta exportar o importar, ver
/// docs/pantallas/flujo-descripcion.md#ventana-5--configuración.
Future<void> mostrarDialogoCatalogo(BuildContext context, WidgetRef ref) async {
  final accion = await showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Catálogo (.tiketdata)'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, 'exportar'),
          child: const Text('Exportar catálogo actual'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, 'importar'),
          child: const Text('Importar catálogo'),
        ),
      ],
    ),
  );
  if (accion == null || !context.mounted) return;

  if (accion == 'exportar') {
    final resultado = await ref.read(tiketdataNotifierProvider.notifier).exportarCatalogo();
    if (!context.mounted) return;
    _mostrarMensaje(context, switch (resultado) {
      ResultadoTiketdata.ok => 'Catálogo exportado',
      ResultadoTiketdata.cancelado => null,
      ResultadoTiketdata.error => 'No se pudo exportar el catálogo',
    });
    return;
  }

  final modo = await showDialog<ModoImportacion>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('¿Reemplazar o fusionar?'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, ModoImportacion.fusionar),
          child: const Text('Fusionar — agrega/actualiza, no toca el resto'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, ModoImportacion.reemplazar),
          child: const Text('Reemplazar — descontinúa lo que no venga en el archivo'),
        ),
      ],
    ),
  );
  if (modo == null || !context.mounted) return;

  if (modo == ModoImportacion.reemplazar) {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Reemplazar catálogo?'),
        content: const Text(
          'Todo producto o categoría activa que no esté en el archivo se descontinuará '
          '(no se borra, queda como descontinuado — se puede revisar en el listado).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !context.mounted) return;
  }

  final resultado = await ref.read(tiketdataNotifierProvider.notifier).importarCatalogo(modo);
  if (!context.mounted) return;
  _mostrarMensaje(context, switch (resultado) {
    ResultadoTiketdata.ok => 'Catálogo importado',
    ResultadoTiketdata.cancelado => null,
    ResultadoTiketdata.error => 'No se pudo importar el catálogo (¿archivo válido?)',
  });
}
