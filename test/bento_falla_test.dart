import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/ui/bento_falla.dart';

/// Lo que se le muestra a quien atiende cuando algo falla.
///
/// El caso que lo motivó: Reportes falló en el teléfono y apareció un
/// `DatabaseException` con el SQL completo a pantalla llena. El error estaba
/// capturado; lo que faltaba era contarlo en el idioma de quien lo lee.
void main() {
  Future<void> montar(WidgetTester tester, Widget falla) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(AcentoTinte.oro, brightness: Brightness.dark),
        home: Scaffold(body: falla),
      ),
    );
  }

  testWidgets('en producción no se filtra el detalle técnico', (tester) async {
    await montar(
      tester,
      const BentoFalla(
        mensaje: 'No se pudieron cargar las ventas del período.',
        error: 'DatabaseException(no such table: linea_venta) SELECT * FROM …',
        mostrarDetalle: false,
      ),
    );

    expect(find.text('No se pudieron cargar las ventas del período.'), findsOneWidget);
    expect(find.textContaining('no such table'), findsNothing);
    expect(find.text('Detalle técnico'), findsNothing);
  });

  testWidgets('en depuración el detalle está, pero plegado', (tester) async {
    await montar(
      tester,
      const BentoFalla(
        mensaje: 'No se pudieron cargar las ventas del período.',
        error: 'DatabaseException(no such table: linea_venta)',
        mostrarDetalle: true,
      ),
    );

    expect(find.text('Detalle técnico'), findsOneWidget);
    // Plegado: el volcado no se ve hasta que se pide.
    expect(find.textContaining('no such table'), findsNothing);

    await tester.tap(find.text('Detalle técnico'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no such table'), findsOneWidget);
  });

  testWidgets('reintentar solo aparece si hay algo que reintentar', (tester) async {
    await montar(tester, const BentoFalla(mensaje: 'Falló algo.'));
    expect(find.text('Reintentar'), findsNothing);

    var intentos = 0;
    await montar(tester, BentoFalla(mensaje: 'Falló algo.', onReintentar: () => intentos++));
    await tester.tap(find.text('Reintentar'));
    expect(intentos, 1);
  });
}
