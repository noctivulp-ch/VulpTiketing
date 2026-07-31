import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/bento_aviso.dart';
import '../../../core/theme/bento_theme.dart';
import '../../auth/sesion_notifier.dart';

/// Cambiar la contraseña local del dispositivo — panel inline de
/// Configuración (antes un `AlertDialog`; la app evita overlays/menús
/// emergentes en la medida de lo posible). Pide la contraseña actual antes
/// de aceptar la nueva, y confirmación de la nueva (a diferencia del Login,
/// acá sí hay riesgo real de errar un typo y quedar afuera sin querer).
class PanelCambiarContrasena extends ConsumerStatefulWidget {
  const PanelCambiarContrasena({super.key});

  @override
  ConsumerState<PanelCambiarContrasena> createState() => _PanelCambiarContrasenaState();
}

class _PanelCambiarContrasenaState extends ConsumerState<PanelCambiarContrasena> {
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
    final ok = await ref
        .read(sesionNotifierProvider.notifier)
        .cambiarContrasena(rol, _actualController.text, _nuevaController.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _guardando = false;
        _error = 'Contraseña actual incorrecta';
      });
      return;
    }
    _actualController.clear();
    _nuevaController.clear();
    _confirmarController.clear();
    setState(() => _guardando = false);
    mostrarAviso(context, '✓ Contraseña actualizada');
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Cambiar contraseña', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: BentoSpacing.gapCelda),
          TextFormField(
            controller: _actualController,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Contraseña actual', errorText: _error),
            validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: BentoSpacing.unidad),
          TextFormField(
            controller: _nuevaController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nueva contraseña'),
            validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: BentoSpacing.unidad),
          TextFormField(
            controller: _confirmarController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirmar nueva contraseña'),
            validator: (v) =>
                v != _nuevaController.text ? 'No coincide con la nueva contraseña' : null,
          ),
          const SizedBox(height: BentoSpacing.gapCelda),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _guardando ? null : _confirmar,
              child: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}
