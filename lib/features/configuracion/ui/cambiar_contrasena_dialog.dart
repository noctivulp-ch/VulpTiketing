import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/sesion_notifier.dart';

/// Cambiar la contraseña local del dispositivo — solo desde Configuración,
/// ya logueado (decisión 0011, addendum). Pide la contraseña actual antes
/// de aceptar la nueva, y confirmación de la nueva (a diferencia del Login,
/// acá sí hay riesgo real de errar un typo y quedar afuera sin querer).
class CambiarContrasenaDialog extends ConsumerStatefulWidget {
  const CambiarContrasenaDialog({super.key});

  @override
  ConsumerState<CambiarContrasenaDialog> createState() => _CambiarContrasenaDialogState();
}

class _CambiarContrasenaDialogState extends ConsumerState<CambiarContrasenaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!_formKey.currentState!.validate()) return;
    final rol = ref.read(sesionNotifierProvider);
    if (rol == null) return;

    setState(() {
      _guardando = true;
      _error = null;
    });
    final ok = await ref.read(sesionNotifierProvider.notifier).cambiarContrasena(
          rol,
          _actualController.text,
          _nuevaController.text,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _guardando = false;
        _error = 'Contraseña actual incorrecta';
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contraseña actualizada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _actualController,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Contraseña actual', errorText: _error),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _nuevaController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña'),
              validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _confirmarController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar nueva contraseña'),
              validator: (v) =>
                  v != _nuevaController.text ? 'No coincide con la nueva contraseña' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _confirmar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
