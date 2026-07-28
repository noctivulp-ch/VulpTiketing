import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/bento_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/sesion_notifier.dart';
import 'features/dashboard/dashboard_shell.dart';

class VulpTiketingApp extends ConsumerWidget {
  const VulpTiketingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rol = ref.watch(sesionNotifierProvider);

    return MaterialApp(
      title: 'VulpTiketing',
      theme: buildBentoTheme(),
      home: rol == null ? const LoginScreen() : const DashboardShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
