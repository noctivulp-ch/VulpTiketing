import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/version.dart';
import 'package:vulp_tiketing/features/configuracion/ui/panel_acerca_de.dart';

/// La pantalla de Acerca de, y sobre todo su firma.
///
/// El enlace va **embebido y sin decoración**: en pantalla se lee como una firma,
/// no como un botón. Eso tiene dos consecuencias que hay que sostener a la vez, y
/// son lo que estas pruebas vigilan:
///
/// - **No se ve la dirección.** Es el pedido del dueño: la marca de autoría no
///   tiene que parecer una invitación a pagar. La app es a medida para un
///   familiar y no cobra nada.
/// - **Sí se anuncia a quien no ve la pantalla.** Un enlace invisible es una
///   decisión de diseño para quien mira; con TalkBack sería un elemento que hace
///   algo inesperado al tocarlo, y eso no es discreción, es una trampa.
void main() {
  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(AcentoTinte.oro, brightness: Brightness.dark),
        home: const Scaffold(body: PanelAcercaDe()),
      ),
    );
    await tester.pump();
  }

  testWidgets('muestra el nombre visible, no el del paquete', (tester) async {
    await montar(tester);

    expect(find.text('VulpTiketing'), findsOneWidget);
    expect(find.textContaining('vulp_tiketing'), findsNothing);
  });

  testWidgets('muestra la versión y el número de compilación', (tester) async {
    // El build importa: cuando algo no cuadra en un teléfono, lo primero es
    // saber si corre el mismo código que los demás.
    await montar(tester);

    expect(find.text('Versión $versionApp (build $compilacionApp)'), findsOneWidget);
  });

  testWidgets('firma con el autor', (tester) async {
    await montar(tester);

    expect(find.text('Hecho por NoctiVulp'), findsOneWidget);
  });

  testWidgets('la dirección NO se ve en ninguna parte', (tester) async {
    await montar(tester);

    expect(find.textContaining('patreon'), findsNothing);
    expect(find.textContaining('http'), findsNothing);
  });

  testWidgets('la firma se puede tocar y el objetivo llega a 48 dp', (tester) async {
    await montar(tester);

    final tocable = find.ancestor(
      of: find.text('Hecho por NoctiVulp'),
      matching: find.byType(InkWell),
    );
    expect(tocable, findsOneWidget);
    expect(tester.getSize(tocable).height, greaterThanOrEqualTo(48));
  });

  testWidgets('con lector de pantalla sí se anuncia como enlace', (tester) async {
    final semantica = tester.ensureSemantics();
    await montar(tester);

    expect(find.bySemanticsLabel('Hecho por NoctiVulp — abre la página del autor'), findsOneWidget);
    semantica.dispose();
  });
}
