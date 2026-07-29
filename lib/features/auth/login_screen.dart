import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bento_icon.dart';
import 'sesion_notifier.dart';

/// Ver docs/pantallas/flujo-descripcion.md#login--setup y
/// docs/pantallas/prototipos-ascii.md#login--setup.
/// Solo se ve la primera vez o tras cerrar sesion (cambio de rol en un
/// dispositivo compartido, no rutinario). La contrasena siempre existe
/// (de fabrica o ya cambiada desde Configuracion) — este flujo nunca
/// "crea" una contrasena, solo la pide.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  Rol? _rolSeleccionado;
  final _contrasenaController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _contrasenaController.dispose();
    super.dispose();
  }

  void _elegirRol(Rol rol) {
    setState(() {
      _rolSeleccionado = rol;
      _error = null;
    });
  }

  void _volver() {
    setState(() {
      _rolSeleccionado = null;
      _error = null;
      _contrasenaController.clear();
    });
  }

  Future<void> _entrar() async {
    final rol = _rolSeleccionado;
    if (rol == null) return;
    final ok = await ref
        .read(sesionNotifierProvider.notifier)
        .iniciarSesion(rol, _contrasenaController.text);
    if (!ok && mounted) {
      setState(() => _error = 'Contraseña incorrecta');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('VulpTiketing', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 32),
                if (_rolSeleccionado == null) ...[
                  Row(
                    children: [
                      Expanded(child: _TarjetaRol(
                        rol: Rol.gerente,
                        icono: 'rol_gerente',
                        onTap: () => _elegirRol(Rol.gerente),
                      )),
                      const SizedBox(width: 16),
                      Expanded(child: _TarjetaRol(
                        rol: Rol.registradora,
                        icono: 'rol_registradora',
                        onTap: () => _elegirRol(Rol.registradora),
                      )),
                    ],
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _volver,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Volver'),
                    ),
                  ),
                  _TarjetaRol(
                    rol: _rolSeleccionado!,
                    icono: _rolSeleccionado == Rol.gerente
                        ? 'rol_gerente'
                        : 'rol_registradora',
                    seleccionada: true,
                    onTap: _volver,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _contrasenaController,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _entrar, child: const Text('Entrar')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaRol extends StatelessWidget {
  const _TarjetaRol({
    required this.rol,
    required this.icono,
    required this.onTap,
    this.seleccionada = false,
  });

  final Rol rol;
  final String icono;
  final VoidCallback onTap;
  final bool seleccionada;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: seleccionada ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              BentoIcon(icono, size: 48, activo: seleccionada),
              const SizedBox(height: 8),
              Text(rol == Rol.gerente ? 'Gerente' : 'Registradora'),
            ],
          ),
        ),
      ),
    );
  }
}
