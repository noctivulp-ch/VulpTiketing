import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/bento_bandeja.dart';
import '../../core/theme/bento_cuadricula.dart';
import '../../core/theme/bento_icon.dart';
import '../../core/theme/bento_theme.dart';
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
    final laca = lacaDe(context);

    // El titulo va sobre la BANDEJA, asi que lleva el color de texto de
    // bandeja explicito. Con el color de texto de pozo (`onSurface`, casi
    // negro en modo claro) quedaba invisible sobre el marco oscuro — fue un
    // bug real: la contrasena se escribia pero no se veia.
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(BentoSpacing.rim),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'VulpTiketing',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: laca.textoEnBandeja),
                ),
                const SizedBox(height: BentoSpacing.gapGrupo * 1.5),
                if (_rolSeleccionado == null) ...[
                  // Mitades exactas de la retícula en cualquier tamaño: los dos
                  // roles pesan lo mismo, y la elección se hace de un vistazo.
                  BentoCuadricula(
                    hijos: [
                      BentoCelda(
                        compacto: 3,
                        medio: 3,
                        amplio: 3,
                        hijo: _TarjetaRol(
                          rol: Rol.gerente,
                          icono: 'rol_gerente',
                          onTap: () => _elegirRol(Rol.gerente),
                        ),
                      ),
                      BentoCelda(
                        compacto: 3,
                        medio: 3,
                        amplio: 3,
                        hijo: _TarjetaRol(
                          rol: Rol.registradora,
                          icono: 'rol_registradora',
                          onTap: () => _elegirRol(Rol.registradora),
                        ),
                      ),
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
                  const SizedBox(height: BentoSpacing.unidad),
                  _TarjetaRol(
                    rol: _rolSeleccionado!,
                    icono: _rolSeleccionado == Rol.gerente
                        ? 'rol_gerente'
                        : 'rol_registradora',
                    seleccionada: true,
                    onTap: _volver,
                  ),
                  const SizedBox(height: BentoSpacing.pared),
                  // El campo va DENTRO de un pozo: es contenido, y el
                  // contenido vive en compartimentos, nunca suelto sobre el
                  // marco (DESIGN.md, regla 2).
                  BentoPozo(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BentoSpacing.paddingCelda,
                      vertical: BentoSpacing.unidad / 2,
                    ),
                    child: TextField(
                      controller: _contrasenaController,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        errorText: _error,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onSubmitted: (_) => _entrar(),
                    ),
                  ),
                  const SizedBox(height: BentoSpacing.pared),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: _entrar, child: const Text('Entrar')),
                  ),
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
    // Antes: `Card` rellena de `primaryContainer` al estar seleccionada, que
    // con la paleta de laca es un bloque de oro macizo — y el icono, que se
    // tinta con el mismo acento, quedaba oro sobre oro (invisible). Ahora la
    // seleccion se dice como en el resto del sistema: el compartimento
    // elegido es el que esta hundido, con la cresta en oro.
    return BentoPozo(
      onTap: onTap,
      seleccionado: seleccionada,
      padding: const EdgeInsets.all(BentoSpacing.paddingCeldaGrande),
      child: Column(
        children: [
          BentoIcon(icono, size: 48, activo: seleccionada),
          const SizedBox(height: BentoSpacing.unidad),
          Text(rol == Rol.gerente ? 'Gerente' : 'Registradora'),
        ],
      ),
    );
  }
}
