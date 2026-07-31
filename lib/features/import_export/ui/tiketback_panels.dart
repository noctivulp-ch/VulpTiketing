import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_corner_notice.dart';
import '../../../core/theme/bento_theme.dart';
import '../tiketback_notifier.dart';
import '../tiketback_service.dart';

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

/// Qué reemplaza cada alcance, en las palabras del negocio.
///
/// El aviso nombra lo que se va a pisar en vez de decir "irreversible" a secas:
/// advertir de más ante una restauración acotada entrena a ignorar el aviso, y
/// entonces no protege el día que sí importa.
({String titulo, String detalle, String advertencia}) _textoDe(AlcanceRestauracion alcance) {
  switch (alcance) {
    case AlcanceRestauracion.todo:
      return (
        titulo: 'Todo',
        detalle: 'Menú y ventas',
        advertencia:
            'Se reemplazan TODOS los datos del dispositivo —el menú y '
            'todas las ventas— por los del backup. Las ventas registradas '
            'después de ese backup se pierden.',
      );
    case AlcanceRestauracion.soloMenu:
      return (
        titulo: 'Solo el menú',
        detalle: 'Productos y categorías',
        advertencia:
            'Se reemplaza el menú por el del backup. Las ventas no se '
            'tocan: siguen todas donde están.',
      );
    case AlcanceRestauracion.soloVentas:
      return (
        titulo: 'Solo las ventas',
        detalle: 'El historial de ventas',
        advertencia:
            'Se reemplazan las ventas por las del backup. El menú '
            'actual no se toca. Las ventas registradas después de ese backup '
            'se pierden.',
      );
  }
}

enum _PasoRestaurar { elegirAlcance, confirmar, contrasena }

/// Panel inline de Configuración (antes dos `AlertDialog` encadenados:
/// confirmación + contraseña). Restaurar es SIEMPRE reemplazo (0017); desde la
/// 0025 el usuario elige el alcance, porque menú y ventas ya son piezas
/// separables dentro del mismo backup.
class PanelRestaurarBackup extends ConsumerStatefulWidget {
  const PanelRestaurarBackup({super.key});

  @override
  ConsumerState<PanelRestaurarBackup> createState() => _PanelRestaurarBackupState();
}

class _PanelRestaurarBackupState extends ConsumerState<PanelRestaurarBackup> {
  final _contrasenaController = TextEditingController();
  _PasoRestaurar _paso = _PasoRestaurar.elegirAlcance;
  AlcanceRestauracion _alcance = AlcanceRestauracion.todo;
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
    final resultado = await ref
        .read(tiketbackNotifierProvider.notifier)
        .restaurar(contrasena, alcance: _alcance);
    if (!mounted) return;
    setState(() {
      _restaurando = false;
      _paso = _PasoRestaurar.elegirAlcance;
    });
    _contrasenaController.clear();
    final mensaje = _mensaje(resultado, accion: 'restaurar');
    if (mensaje != null) mostrarNotificacionEsquina(context, mensaje);
  }

  @override
  Widget build(BuildContext context) {
    switch (_paso) {
      case _PasoRestaurar.elegirAlcance:
        return _pasoElegirAlcance(context);
      case _PasoRestaurar.confirmar:
        return _pasoConfirmar(context);
      case _PasoRestaurar.contrasena:
        return _pasoContrasena(context);
    }
  }

  Widget _pasoElegirAlcance(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Restaurar backup', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.unidad),
        const Text('¿Qué querés traer del backup?'),
        const SizedBox(height: BentoSpacing.gapCelda),
        for (final alcance in AlcanceRestauracion.values) ...[
          _BotonAlcance(
            texto: _textoDe(alcance),
            onPressed: () => setState(() {
              _alcance = alcance;
              _paso = _PasoRestaurar.confirmar;
            }),
          ),
          const SizedBox(height: BentoSpacing.unidad),
        ],
      ],
    );
  }

  Widget _pasoConfirmar(BuildContext context) {
    final texto = _textoDe(_alcance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Restaurar: ${texto.titulo}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: BentoSpacing.unidad),
        Text(texto.advertencia),
        const SizedBox(height: BentoSpacing.gapCelda),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _paso = _PasoRestaurar.elegirAlcance),
              child: const Text('Atrás'),
            ),
            const SizedBox(width: BentoSpacing.unidad),
            FilledButton(
              onPressed: () => setState(() => _paso = _PasoRestaurar.contrasena),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pasoContrasena(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Restaurar: ${_textoDe(_alcance).titulo}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
              onPressed: _restaurando
                  ? null
                  : () => setState(() => _paso = _PasoRestaurar.elegirAlcance),
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

class _BotonAlcance extends StatelessWidget {
  const _BotonAlcance({required this.texto, required this.onPressed});

  final ({String titulo, String detalle, String advertencia}) texto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BentoSpacing.unidad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(texto.titulo, style: tema.textTheme.titleSmall),
              Text(
                texto.detalle,
                style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
