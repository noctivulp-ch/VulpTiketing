import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_tallado.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';

/// Un texto tallado se anuncia **una vez**, no tres.
///
/// El relieve pinta el mismo glifo tres veces —sombra, luz y glifo— y las tres
/// copias entraban en el árbol de accesibilidad. Consecuencias:
///
/// - Con TalkBack, cada producto de la carta se leía tres veces seguidas.
/// - La navegación por semántica del harness recibía
///   `"Arroz cantones (entero)\nArroz cantones (entero)\nArroz cantones
///   (entero)"` como etiqueta de un botón.
///
/// Se descubrió al construir la navegación por semántica, no mirando la
/// pantalla: **el efecto visual es idéntico con y sin el fallo**, así que no
/// había forma de verlo con capturas. Es el tipo de cosa que solo aparece
/// cuando algo lee la app en vez de fotografiarla.
void main() {
  Future<void> montar(WidgetTester tester, Widget hijo) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(AcentoTinte.oro),
        home: Scaffold(body: Center(child: hijo)),
      ),
    );
    await tester.pump();
  }

  testWidgets('el relieve no mete el texto tres veces en la semántica', (tester) async {
    final semantica = tester.ensureSemantics();

    await montar(tester, BentoTextoTallado('Arroz cantones', sobre: const Color(0xFF3A1E1B)));

    // Una sola vez: las dos capas de relieve son decoración y van bajo
    // `ExcludeSemantics`.
    expect(find.bySemanticsLabel('Arroz cantones'), findsOneWidget);
    semantica.dispose();
  });

  testWidgets('y el texto se sigue viendo tres veces, que es el efecto', (tester) async {
    // La otra mitad: quitar las copias de la SEMÁNTICA no puede quitarlas del
    // dibujo, o se pierde el relieve que es la identidad visual de la app.
    await montar(tester, BentoTextoTallado('Arroz cantones', sobre: const Color(0xFF3A1E1B)));

    expect(find.text('Arroz cantones'), findsNWidgets(3));
  });

  testWidgets('con el relieve apagado tampoco se duplica', (tester) async {
    // Con `profundidad: 0` el widget devuelve el hijo tal cual. Se comprueba
    // que ese camino no reintroduzca copias.
    final semantica = tester.ensureSemantics();

    await montar(
      tester,
      const BentoTallado(sobre: Color(0xFF3A1E1B), profundidad: 0, child: Text('Casado')),
    );

    expect(find.bySemanticsLabel('Casado'), findsOneWidget);
    semantica.dispose();
  });
}
