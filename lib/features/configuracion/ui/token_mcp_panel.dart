import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/bento_bandeja.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/ui/bento_aviso.dart';
import '../../../core/ui/bento_dialogo.dart';
import '../../auth/sesion_notifier.dart';
import '../token_mcp_service.dart';

/// El token que permite manejar la app desde fuera (el harness del MCP).
///
/// Pide la contraseña **antes de enseñarlo**, no antes de generarlo: la
/// contraseña está acá para que el token no quede a la vista de quien agarre el
/// teléfono desbloqueado. No lo determina — el token es aleatorio, y esa es
/// justamente la razón de que rotarlo sea gratis.
///
/// Que arranque sin token es deliberado: mientras nadie lo pida, no hay llave
/// que robar y el harness no puede conectarse de ninguna manera.
class PanelTokenMcp extends ConsumerStatefulWidget {
  const PanelTokenMcp({super.key});

  @override
  ConsumerState<PanelTokenMcp> createState() => _PanelTokenMcpState();
}

class _PanelTokenMcpState extends ConsumerState<PanelTokenMcp> {
  final _contrasenaController = TextEditingController();
  String? _error;
  bool _ocupado = false;

  /// El token en claro, solo mientras esta pantalla siga abierta. No se guarda
  /// en el estado de ningún provider: al salir del panel se olvida y hay que
  /// volver a escribir la contraseña.
  String? _revelado;

  @override
  void dispose() {
    _contrasenaController.dispose();
    super.dispose();
  }

  Future<bool> _contrasenaOk() async {
    final rol = ref.read(sesionNotifierProvider);
    if (rol == null) return false;
    return ref
        .read(sesionNotifierProvider.notifier)
        .confirmarContrasena(rol, _contrasenaController.text);
  }

  Future<void> _conContrasena(Future<void> Function() accion) async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    final ok = await _contrasenaOk();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _ocupado = false;
        _error = 'Contraseña incorrecta';
      });
      return;
    }
    await accion();
    if (mounted) {
      setState(() {
        _ocupado = false;
        _contrasenaController.clear();
      });
    }
  }

  Future<void> _mostrar() => _conContrasena(() async {
    final token = await ref.read(tokenMcpServiceProvider).leer();
    if (!mounted) return;
    setState(() => _revelado = token);
    if (token == null && mounted) {
      mostrarAviso(context, 'Todavía no hay token. Generá uno.');
    }
  });

  Future<void> _generar() => _conContrasena(() async {
    final token = await ref.read(tokenMcpServiceProvider).generar();
    ref.invalidate(tokenMcpProvider);
    if (!mounted) return;
    setState(() => _revelado = token);
    mostrarAviso(context, '✓ Token nuevo. El anterior dejó de servir.');
  });

  Future<void> _revocar() => _conContrasena(() async {
    await ref.read(tokenMcpServiceProvider).revocar();
    ref.invalidate(tokenMcpProvider);
    if (!mounted) return;
    setState(() => _revelado = null);
    mostrarAviso(context, '✓ Acceso revocado');
  });

  @override
  Widget build(BuildContext context) {
    final hayToken = ref.watch(tokenMcpProvider).valueOrNull != null;
    final textos = Theme.of(context).textTheme;

    return BentoPanel(
      titulo: 'Acceso de herramientas',
      contenido: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // El aviso va PRIMERO y en rojo: un build que acepta un token fijo y
          // conocido no puede parecerse a uno normal, y esta pantalla es el
          // único sitio donde se puede notar la diferencia.
          if (TokenMcpService.esBuildDeDesarrollo) ...[
            _AvisoDeDesarrollo(),
            const SizedBox(height: BentoSpacing.unidad),
          ],
          Text(
            hayToken
                ? 'Hay un token activo. Quien lo tenga puede manejar esta app '
                      'desde una computadora conectada por cable.'
                : 'Sin token: nada de fuera puede manejar esta app. Generá uno '
                      'solo si vas a asistirte con una herramienta externa.',
            style: textos.bodySmall,
          ),
          const SizedBox(height: BentoSpacing.unidad),
          TextField(
            controller: _contrasenaController,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Contraseña', errorText: _error),
            onSubmitted: (_) => _ocupado ? null : _mostrar(),
          ),
          if (_revelado != null) ...[
            const SizedBox(height: BentoSpacing.unidad),
            Text('Token', style: textos.labelLarge),
            const SizedBox(height: BentoSpacing.unidad / 2),
            BentoPozo(
              // Se toca para copiar: nadie va a transcribir a mano cuarenta y
              // tres caracteres al azar, y equivocarse en uno da un error que
              // no se distingue de "el token está mal".
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: _revelado!));
                if (context.mounted) mostrarAviso(context, '✓ Token copiado');
              },
              child: Row(
                children: [
                  Expanded(child: SelectableText(_revelado!, style: textos.bodySmall)),
                  const Icon(Icons.copy_outlined, size: 18),
                ],
              ),
            ),
            const SizedBox(height: BentoSpacing.unidad / 2),
            Text(
              'Dáselo solo a la herramienta que estés usando. Si dejás de '
              'usarla, revocá.',
              style: textos.bodySmall,
            ),
          ],
        ],
      ),
      acciones: [
        if (hayToken)
          TextButton(onPressed: _ocupado ? null : _revocar, child: const Text('Revocar')),
        if (hayToken)
          TextButton(onPressed: _ocupado ? null : _mostrar, child: const Text('Mostrar')),
        FilledButton(
          onPressed: _ocupado ? null : _generar,
          child: Text(hayToken ? 'Generar otro' : 'Generar'),
        ),
      ],
    );
  }
}

/// Lo que separa un build de pruebas de uno para el negocio.
///
/// El token de desarrollo es fijo y está escrito en el repositorio, así que
/// cualquiera que tenga el código puede manejar un aparato con este build. En
/// una máquina de desarrollo eso es exactamente lo que se quiere; en el
/// mostrador de la soda, no.
///
/// Por eso el aviso es imposible de confundir con información: usa el color de
/// error del tema, dice qué hay que hacer, y no se puede cerrar.
class _AvisoDeDesarrollo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(BentoRadius.pozo),
        border: Border.all(color: scheme.error),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BentoSpacing.unidad),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 20, color: scheme.onErrorContainer),
            const SizedBox(width: BentoSpacing.unidad),
            Expanded(
              child: Text(
                'BUILD DE PRUEBAS. Acepta un token fijo y conocido, así que '
                'cualquiera con el código puede manejar este aparato. '
                'Antes de dejarlo en el negocio hay que reinstalar la app con '
                '`flutter build apk --release`.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
