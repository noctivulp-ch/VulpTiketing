import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tiketback_notifier.dart';

Future<String?> _pedirContrasena(BuildContext context, String titulo, String boton) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Contraseña de exportación'),
        onSubmitted: (v) => Navigator.pop(dialogContext, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(boton),
        ),
      ],
    ),
  );
}

void _mostrarMensaje(BuildContext context, String? mensaje) {
  if (mensaje == null) return; // cancelado por el usuario, sin feedback necesario
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
}

Future<void> mostrarDialogoExportarTiketback(BuildContext context, WidgetRef ref) async {
  final contrasena = await _pedirContrasena(context, 'Exportar backup', 'Continuar');
  if (contrasena == null || contrasena.isEmpty || !context.mounted) return;

  final resultado = await ref.read(tiketbackNotifierProvider.notifier).exportar(contrasena);
  if (!context.mounted) return;
  _mostrarMensaje(context, switch (resultado) {
    ResultadoTiketback.ok => 'Backup exportado',
    ResultadoTiketback.cancelado => null,
    ResultadoTiketback.contrasenaIncorrecta => null, // no aplica al exportar
    ResultadoTiketback.error => 'No se pudo exportar el backup',
  });
}

/// Restaurar es SIEMPRE reemplazo total (0017) — pide confirmación
/// explícita antes de pedir la contraseña, es irreversible.
Future<void> mostrarDialogoRestaurarTiketback(BuildContext context, WidgetRef ref) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿Restaurar backup?'),
      content: const Text(
        'Esto reemplaza TODOS los datos actuales del dispositivo por los del backup. No se puede deshacer.',
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

  final contrasena = await _pedirContrasena(context, 'Restaurar backup', 'Restaurar');
  if (contrasena == null || contrasena.isEmpty || !context.mounted) return;

  final resultado = await ref.read(tiketbackNotifierProvider.notifier).restaurar(contrasena);
  if (!context.mounted) return;
  _mostrarMensaje(context, switch (resultado) {
    ResultadoTiketback.ok => 'Backup restaurado',
    ResultadoTiketback.cancelado => null,
    ResultadoTiketback.contrasenaIncorrecta => 'Contraseña incorrecta',
    ResultadoTiketback.error =>
      'No se pudo restaurar el backup (¿archivo corrupto o contraseña equivocada?)',
  });
}
