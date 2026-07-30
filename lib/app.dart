import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/bento_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/sesion_notifier.dart';
import 'features/configuracion/preferencias_notifier.dart';
import 'features/dashboard/dashboard_shell.dart';

class VulpTiketingApp extends ConsumerWidget {
  const VulpTiketingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rol = ref.watch(sesionNotifierProvider);
    // Hasta que no se sabe si había sesión guardada no se decide qué mostrar:
    // sin esta espera se vería un parpadeo del Login en cada apertura, justo
    // antes de saltar al Dashboard.
    final restaurando = ref.watch(sesionRestauradaProvider).isLoading;
    final preferencias = ref.watch(preferenciasNotifierProvider).valueOrNull;
    final acento = preferencias?.acento ?? AcentoTinte.oro;
    final modoTema = preferencias?.modoTema ?? ModoTema.sistema;

    return MaterialApp(
      title: 'VulpTiketing',
      theme: buildBentoTheme(acento),
      darkTheme: buildBentoTheme(acento, brightness: Brightness.dark),
      themeMode: switch (modoTema) {
        ModoTema.claro => ThemeMode.light,
        ModoTema.oscuro => ThemeMode.dark,
        ModoTema.sistema => ThemeMode.system,
      },
      home: restaurando
          ? const _Arranque()
          : (rol == null ? const LoginScreen() : const DashboardShell()),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Bandeja vacía mientras se recupera la sesión. Sin texto ni indicador: dura
/// una lectura de almacenamiento seguro, y un spinner que aparece y desaparece
/// en ese lapso se lee como un parpadeo, no como progreso.
class _Arranque extends StatelessWidget {
  const _Arranque();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
