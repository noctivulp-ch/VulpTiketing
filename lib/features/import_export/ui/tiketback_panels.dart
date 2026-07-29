import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_corner_notice.dart';
import '../../../core/theme/bento_theme.dart';
import '../tiketback_notifier.dart';

String? _mensaje(ResultadoTiketback resultado, {required String accion}) {
  switch (resultado) {
    case ResultadoTiketback.ok:
      return accion == 'exportar' ? '✓ Backup exportado' : '✓ Backup restaurado';
    case ResultadoTiketback.cancelado:
      return null; // cancelado por el usuario (selector de archivo), sin feedback necesario
    case ResultadoTiketback.contrasenaIncorrecta:
      return 'Contraseña incorrecta';
    case ResultadoTiketback.error:
      return accion == 'exportar'
          ? 'No se pudo exportar el backup'
          : 'No se pudo restaurar el backup (¿archivo corrupto o contraseña equivocada?)';
  }
}

/// Panel inline de Configuración (antes un `AlertDialog` pidiendo la
/// contraseña de exportación).
class PanelExportarBackup extends ConsumerStatefulWidget {
  const PanelExportarBackup({super.key});

  @override
  ConsumerState<PanelExportarBackup> createState() => _PanelExportarBackupState();
}

class _PanelExportarBackupState extends ConsumerState<PanelExportarBackup> {
  final _contrasenaController = TextEditingController();
  bool _exportando = false;

  @override
  void dispose() {
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _exportar() async {
    final contrasena = _contrasenaController.text;
    if (contrasena.isEmpty) return;
    setState(() => _exportando = true);
    final resultado = await ref.read(tiketbackNotifierProvider.notifier).exportar(contrasena);
    if (!mounted) return;
    setState(() => _exportando = false);
    _contrasenaController.clear();
    final mensaje = _mensaje(resultado, accion: 'exportar');
    if (mensaje != null) mostrarNotificacionEsquina(context, mensaje);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Exportar backup', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.gapCelda),
        TextField(
          controller: _contrasenaController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Contraseña de exportación'),
          onSubmitted: (_) => _exportar(),
        ),
        const SizedBox(height: BentoSpacing.gapCelda),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _exportando ? null : _exportar,
            child: const Text('Exportar'),
          ),
        ),
      ],
    );
  }
}

/// Panel inline de Configuración (antes dos `AlertDialog` encadenados:
/// confirmación + contraseña). Restaurar es SIEMPRE reemplazo total (0017)
/// e irreversible — el aviso sigue siendo un paso explícito y separado del
/// campo de contraseña, ahora dentro del mismo panel en vez de un diálogo.
class PanelRestaurarBackup extends ConsumerStatefulWidget {
  const PanelRestaurarBackup({super.key});

  @override
  ConsumerState<PanelRestaurarBackup> createState() => _PanelRestaurarBackupState();
}

class _PanelRestaurarBackupState extends ConsumerState<PanelRestaurarBackup> {
  final _contrasenaController = TextEditingController();
  bool _confirmado = false;
  bool _restaurando = false;

  @override
  void dispose() {
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<void> _restaurar() async {
    final contrasena = _contrasenaController.text;
    if (contrasena.isEmpty) return;
    setState(() => _restaurando = true);
    final resultado = await ref.read(tiketbackNotifierProvider.notifier).restaurar(contrasena);
    if (!mounted) return;
    setState(() => _restaurando = false);
    _contrasenaController.clear();
    final mensaje = _mensaje(resultado, accion: 'restaurar');
    if (mensaje != null) mostrarNotificacionEsquina(context, mensaje);
  }

  @override
  Widget build(BuildContext context) {
    if (!_confirmado) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Restaurar backup', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: BentoSpacing.unidad),
          const Text(
            'Esto reemplaza TODOS los datos actuales del dispositivo por los del backup. '
            'No se puede deshacer.',
          ),
          const SizedBox(height: BentoSpacing.gapCelda),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => setState(() => _confirmado = true),
              child: const Text('Continuar'),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Restaurar backup', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.gapCelda),
        TextField(
          controller: _contrasenaController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Contraseña de exportación'),
          onSubmitted: (_) => _restaurar(),
        ),
        const SizedBox(height: BentoSpacing.gapCelda),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _restaurando ? null : () => setState(() => _confirmado = false),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: BentoSpacing.unidad),
            FilledButton(
              onPressed: _restaurando ? null : _restaurar,
              child: const Text('Restaurar'),
            ),
          ],
        ),
      ],
    );
  }
}
