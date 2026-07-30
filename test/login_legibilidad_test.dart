import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_bandeja.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/auth/login_screen.dart';

/// Regresion de un bug real y silencioso: el contenido del login estaba
/// suelto sobre la BANDEJA pero pintado con el color de texto de POZO
/// (`onSurface`, casi negro en modo claro). Compilaba, no lanzaba nada, y
/// pasaba todas las pruebas — pero la contrasena se escribia sin verse, lo
/// que parecia que el teclado no funcionaba.
///
/// La leccion que codifica esta prueba: en este sistema visual el color de
/// texto depende de SOBRE QUE superficie esta, asi que un texto sobre la
/// bandeja tiene que contrastar contra la bandeja, no contra el pozo.
double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final alto = la > lb ? la : lb;
  final bajo = la > lb ? lb : la;
  return (alto + 0.05) / (bajo + 0.05);
}

Widget _envolver(ThemeData tema) {
  return ProviderScope(
    child: MaterialApp(theme: tema, home: const LoginScreen()),
  );
}

void main() {
  for (final brillo in Brightness.values) {
    final tema = buildBentoTheme(AcentoTinte.verdeLaca, brightness: brillo);

    testWidgets('el titulo del login contrasta contra la bandeja en ${brillo.name}', (tester) async {
      await tester.pumpWidget(_envolver(tema));
      await tester.pump();

      final titulo = tester.widget<Text>(find.text('VulpTiketing'));
      final color = titulo.style?.color;
      expect(color, isNotNull, reason: 'el titulo va sobre la bandeja: necesita color explicito');

      final ratio = _contraste(color!, tema.scaffoldBackgroundColor);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: 'titulo sobre bandeja en ${brillo.name}: ${ratio.toStringAsFixed(2)}:1',
      );
    });

    testWidgets('el campo de contraseña vive dentro de un pozo en ${brillo.name}', (tester) async {
      await tester.pumpWidget(_envolver(tema));
      await tester.pump();

      await tester.tap(find.text('Registradora'));
      await tester.pumpAndSettle();

      // Estructural, no cosmetico: si el campo esta dentro de un pozo hereda
      // los colores de contenido correctos por construccion, y no hay que
      // acordarse de parchear el color en cada widget nuevo.
      expect(
        find.ancestor(of: find.byType(TextField), matching: find.byType(BentoPozo)),
        findsOneWidget,
        reason: 'el TextField suelto sobre la bandeja se escribe pero no se ve',
      );
    });
  }
}
