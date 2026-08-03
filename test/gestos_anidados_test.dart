import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/nav/gesto_dos_dedos.dart';
import 'package:vulp_tiketing/core/nav/gesto_navegacion.dart';

/// Los dos gestos conviven ANIDADOS, que es como están en la app: el shell
/// envuelve todo con la navegación de un dedo y cada pantalla pone sus acciones
/// de dos dedos dentro.
///
/// Probarlos por separado no alcanzó: el horizontal de dos dedos no funcionaba
/// en el aparato porque el reconocedor del shell ganaba la arena antes de que
/// el de la pantalla pudiera reclamarlo. Cada widget pasaba su propia prueba.
void main() {
  Future<(List<String>, List<int>)> montar(WidgetTester tester) async {
    final acciones = <String>[];
    final ventanas = <int>[];
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavegacionPorGesto(
            indice: 2,
            cantidad: 5,
            onCambio: ventanas.add,
            child: GestoDeDosDedos(
              alDeslizarIzquierda: () => acciones.add('izquierda'),
              alDeslizarDerecha: () => acciones.add('derecha'),
              alDeslizarAbajo: () => acciones.add('abajo'),
              alDeslizarArriba: () => acciones.add('arriba'),
              child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
            ),
          ),
        ),
      ),
    );
    return (acciones, ventanas);
  }

  Future<void> arrastrar(
    WidgetTester tester, {
    required int dedos,
    double dx = 0,
    double dy = 0,
  }) async {
    final gestos = [
      for (var i = 0; i < dedos; i++) await tester.startGesture(Offset(150.0 + i * 40, 400)),
    ];
    for (var paso = 0; paso < 8; paso++) {
      for (final g in gestos) {
        await g.moveBy(Offset(dx / 8, dy / 8));
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    for (final g in gestos) {
      await g.up();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('dos dedos DE LADO accionan, no navegan', (tester) async {
    final (acciones, ventanas) = await montar(tester);

    await arrastrar(tester, dedos: 2, dx: -160);

    expect(acciones, ['izquierda'], reason: 'la acción de la pantalla tiene que ganar');
    expect(ventanas, isEmpty, reason: 'dos dedos nunca cambian de ventana');
  });

  testWidgets('dos dedos en vertical accionan', (tester) async {
    final (acciones, ventanas) = await montar(tester);

    await arrastrar(tester, dedos: 2, dy: 160);

    expect(acciones, ['abajo']);
    expect(ventanas, isEmpty);
  });

  testWidgets('UN dedo de lado sigue navegando', (tester) async {
    final (acciones, ventanas) = await montar(tester);

    await arrastrar(tester, dedos: 1, dx: -160);

    // A la izquierda es la SIGUIENTE, como pasar la hoja: del 2 al 3.
    expect(ventanas, [3], reason: 'un dedo navega');
    expect(acciones, isEmpty);
  });
}
