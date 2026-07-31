import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/ui/bento_aviso.dart';

/// El aviso único de la app: dos segundos, un toque lo saca antes, se adapta al
/// texto y nunca se encima con otro.
void main() {
  Future<void> montar(WidgetTester tester, {required String mensaje, Size? tamano}) async {
    if (tamano != null) {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(AcentoTinte.oro, brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => mostrarAviso(context, mensaje),
                child: const Text('disparar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('disparar'));
    await tester.pump();
  }

  testWidgets('aparece, se queda dos segundos y se va solo', (tester) async {
    await montar(tester, mensaje: '✓ Venta OK');
    await tester.pumpAndSettle();
    expect(find.text('✓ Venta OK'), findsOneWidget);

    // A la mitad del tiempo sigue: si se fuera antes, no daría tiempo a leerlo.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('✓ Venta OK'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('✓ Venta OK'), findsNothing);
  });

  testWidgets('un toque lo saca antes de los dos segundos', (tester) async {
    await montar(tester, mensaje: '✓ Producto guardado');
    await tester.pumpAndSettle();

    await tester.tap(find.text('✓ Producto guardado'));
    await tester.pumpAndSettle();

    expect(find.text('✓ Producto guardado'), findsNothing);
  });

  testWidgets('un aviso nuevo reemplaza al anterior, no se encima', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(AcentoTinte.oro, brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                for (final texto in ['primero', 'segundo'])
                  ElevatedButton(
                    onPressed: () => mostrarAviso(context, texto),
                    child: Text('disparar $texto'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('disparar primero'));
    await tester.pumpAndSettle();
    expect(find.text('primero'), findsOneWidget);

    await tester.tap(find.text('disparar segundo'));
    await tester.pumpAndSettle();

    // Dos avisos encimados se tapan entre sí y no se lee ninguno: el nuevo
    // reemplaza, no se suma.
    expect(find.text('primero'), findsNothing);
    expect(find.text('segundo'), findsOneWidget);
  });

  testWidgets('un texto largo baja de línea en vez de estirarse', (tester) async {
    const largo = 'No se pudo guardar el reporte porque la carpeta elegida no acepta escritura';
    await montar(tester, mensaje: largo, tamano: const Size(360, 800));
    await tester.pumpAndSettle();

    final caja = tester.getRect(find.text(largo));
    expect(caja.width, lessThanOrEqualTo(180), reason: 'no debe pasar de media pantalla');
    expect(caja.height, greaterThan(40), reason: 'tiene que haber bajado de línea');
  });

  testWidgets('un texto corto no ocupa media pantalla porque sí', (tester) async {
    await montar(tester, mensaje: '✓ OK', tamano: const Size(360, 800));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('✓ OK')).width, lessThan(120));
  });
}
