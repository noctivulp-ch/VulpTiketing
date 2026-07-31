import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_efectos.dart';
import 'package:vulp_tiketing/core/theme/bento_tallado.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';

/// El interruptor de Optimización tiene que APAGAR el efecto de verdad, no
/// solo guardar una preferencia: lo que se prueba es que el árbol de widgets
/// cambia, porque de eso depende la ganancia medida.
void main() {
  Future<void> montar(WidgetTester tester, {required Set<EfectoPesado> apagados}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(
          AcentoTinte.oro,
          brightness: Brightness.dark,
          efectos: BentoEfectos(apagados: apagados),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: BentoTextoTallado(
              '₡15000',
              sobre: lacaDe(context).pozo,
              nivel: TalladoNivel.marcado,
              estilo: const TextStyle(color: Color(0xFFEEEEEE), fontSize: 40),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('con el relieve encendido se pintan las capas de luz y sombra', (tester) async {
    await montar(tester, apagados: const {});

    // Tres textos: sombra, luz y glifo. Es exactamente lo que lo hace caro.
    expect(find.text('₡15000'), findsNWidgets(3));
    expect(find.byType(BentoTallado), findsOneWidget);
  });

  testWidgets('apagado queda un solo texto y sin relieve', (tester) async {
    await montar(tester, apagados: const {EfectoPesado.tallado});

    expect(find.text('₡15000'), findsOneWidget);
    expect(find.byType(BentoTallado), findsNothing);
  });

  testWidgets('apagado el glifo recupera su color pleno', (tester) async {
    // Sin esto, apagar el efecto dejaría el texto con la fusión que existía
    // para vender el relieve: más lavado y peor de leer que con el efecto.
    await montar(tester, apagados: const {EfectoPesado.tallado});

    final texto = tester.widget<Text>(find.text('₡15000'));
    expect(texto.style?.color, const Color(0xFFEEEEEE));
  });

  testWidgets('sin la extensión en el tema, los efectos están encendidos', (tester) async {
    // Un test de widget suelto no arma el tema completo; el default tiene que
    // ser la app tal como se ve, no una versión degradada.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(bentoEfectoActivo(context, EfectoPesado.tallado), isTrue);
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
