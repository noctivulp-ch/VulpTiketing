import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vulp_tiketing/app.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
import 'package:vulp_tiketing/features/dashboard/dashboard_shell.dart';

/// Qué pantalla elige la app al arrancar.
///
/// La sesión se recupera del almacenamiento seguro, así que la app arranca en
/// una pantalla de espera y recién decide cuando esa lectura termina. Los tests
/// sustituyen esa lectura: el almacén seguro no existe en un entorno de prueba,
/// y lo que se quiere probar acá es la DECISIÓN, no el almacén.
void main() {
  Future<void> montar(WidgetTester tester, {Rol? sesionGuardada}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sesionNotifierProvider.overrideWith(() => _SesionFalsa(sesionGuardada))],
        child: const VulpTiketingApp(),
      ),
    );
    // `pump` con tiempo y no `pumpAndSettle`: el Dashboard monta pantallas con
    // indicadores de carga que giran para siempre y dejarían el settle
    // esperando indefinidamente.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('sin sesion guardada arranca en Login', (tester) async {
    await montar(tester);

    expect(find.text('VulpTiketing'), findsOneWidget);
    expect(find.text('Gerente'), findsOneWidget);
    expect(find.text('Registradora'), findsOneWidget);
  });

  testWidgets('con sesion guardada NO vuelve a pedir credenciales', (tester) async {
    // El requisito de `docs/pantallas/flujo-descripcion.md`: el Login se ve
    // "solo la primera vez o después de cerrar sesión explícitamente", no en
    // cada apertura. Estaba escrito y no implementado — la app pedía la
    // contraseña siempre, y el usuario lo reportó desde el teléfono.
    await montar(tester, sesionGuardada: Rol.registradora);

    expect(find.byType(DashboardShell), findsOneWidget);
    expect(find.text('Gerente'), findsNothing, reason: 'no debe pedir el rol otra vez');
    expect(find.text('Registradora'), findsNothing);
  });

  // La sexta ventana, Costeo, es solo del Gerente: la Registradora sigue
  // viendo cinco y sus gestos y atajos no cambian (0040). Dos pruebas y no
  // una: montar dos veces en la misma deja el contenedor de la primera.
  testWidgets('la Registradora no tiene la ventana de Costeo', (tester) async {
    await montar(tester, sesionGuardada: Rol.registradora);
    expect(find.byKey(const ValueKey('nav_configuracion')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav_costeo')), findsNothing);
  });

  testWidgets('el Gerente sí tiene la ventana de Costeo', (tester) async {
    await montar(tester, sesionGuardada: Rol.gerente);
    expect(find.byKey(const ValueKey('nav_costeo')), findsOneWidget);
  });
}

/// Sustituye la lectura del almacén seguro por un valor fijo.
class _SesionFalsa extends SesionNotifier {
  _SesionFalsa(this.guardado);
  final Rol? guardado;

  @override
  Rol? build() => null;

  @override
  Future<void> restaurar() async {
    if (guardado != null) state = guardado;
  }
}
