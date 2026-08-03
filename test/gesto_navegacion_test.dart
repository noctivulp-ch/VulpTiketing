import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/nav/gesto_navegacion.dart';

/// Deslizar de lado cambia de ventana — **con un dedo**.
///
/// La mitad importante de estas pruebas es la que NO navega: dos y tres dedos
/// quedan reservados para acciones, y si este gesto se los queda, esas acciones
/// no se van a poder agregar sin renegociar el gesto entero.
void main() {
  const tamano = Size(360, 800);

  Future<List<int>> montar(WidgetTester tester, {int indice = 2, int cantidad = 5}) async {
    final cambios = <int>[];
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavegacionPorGesto(
            indice: indice,
            cantidad: cantidad,
            onCambio: cambios.add,
            child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
          ),
        ),
      ),
    );
    return cambios;
  }

  testWidgets('deslizar a la izquierda va a la ventana siguiente', (tester) async {
    final cambios = await montar(tester);

    await tester.fling(find.byType(NavegacionPorGesto), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();

    expect(cambios, [3]);
  });

  testWidgets('deslizar a la derecha va a la anterior', (tester) async {
    final cambios = await montar(tester);

    await tester.fling(find.byType(NavegacionPorGesto), const Offset(200, 0), 800);
    await tester.pumpAndSettle();

    expect(cambios, [1]);
  });

  testWidgets('en los extremos no da la vuelta', (tester) async {
    // Saltar de Configuración a Venta Rápida de un tirón desorienta más de lo
    // que ahorra.
    final primera = await montar(tester, indice: 0);
    await tester.fling(find.byType(NavegacionPorGesto), const Offset(200, 0), 800);
    await tester.pumpAndSettle();
    expect(primera, isEmpty);

    final ultima = await montar(tester, indice: 4);
    await tester.fling(find.byType(NavegacionPorGesto), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();
    expect(ultima, isEmpty);
  });

  testWidgets('un roce corto y lento no cambia de ventana', (tester) async {
    // Si cualquier movimiento contara, tocar un producto arrastrando dos
    // milímetros el dedo cambiaría de pantalla.
    final cambios = await montar(tester);

    final gesto = await tester.startGesture(const Offset(180, 400));
    await gesto.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesto.up();
    await tester.pumpAndSettle();

    expect(cambios, isEmpty);
  });

  testWidgets('un arrastre largo cuenta aunque se suelte despacio', (tester) async {
    final cambios = await montar(tester);

    final gesto = await tester.startGesture(const Offset(300, 400));
    for (var i = 0; i < 10; i++) {
      await gesto.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesto.up();
    await tester.pumpAndSettle();

    expect(cambios, [3]);
  });

  testWidgets('DOS dedos no navegan: son para acciones', (tester) async {
    final cambios = await montar(tester);

    final uno = await tester.startGesture(const Offset(300, 380));
    final dos = await tester.startGesture(const Offset(300, 420));
    for (var i = 0; i < 10; i++) {
      await uno.moveBy(const Offset(-25, 0));
      await dos.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await uno.up();
    await dos.up();
    await tester.pumpAndSettle();

    expect(cambios, isEmpty, reason: 'con dos dedos el gesto es otra cosa; navegar sería adivinar');
  });

  testWidgets('un segundo dedo a mitad del arrastre lo anula', (tester) async {
    final cambios = await montar(tester);

    final uno = await tester.startGesture(const Offset(300, 380));
    await uno.moveBy(const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 40));

    final dos = await tester.startGesture(const Offset(300, 420));
    for (var i = 0; i < 6; i++) {
      await uno.moveBy(const Offset(-25, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await uno.up();
    await dos.up();
    await tester.pumpAndSettle();

    expect(cambios, isEmpty);
  });

  testWidgets('lo que ya escucha un toque lo sigue recibiendo', (tester) async {
    // `deferToChild`: el gesto de navegación no puede robarle el toque a un
    // botón, que es lo que pasaría envolviendo todo en un detector opaco.
    var toques = 0;
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavegacionPorGesto(
            indice: 0,
            cantidad: 5,
            onCambio: (_) {},
            child: Center(
              child: FilledButton(onPressed: () => toques++, child: const Text('Cobrar')),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();

    expect(toques, 1);
  });
}
