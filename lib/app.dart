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
    final preferencias = ref.watch(preferenciasNotifierProvider).valueOrNull;
    final acento = preferencias?.acento ?? AcentoTinte.verdeLaca;
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
      home: rol == null ? const LoginScreen() : const DashboardShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
