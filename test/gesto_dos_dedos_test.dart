import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/nav/gesto_dos_dedos.dart';

/// Dos dedos hacen cosas; uno navega.
///
/// Igual que en `gesto_navegacion_test.dart`, la mitad importante es la que NO
/// dispara: si esto reaccionara con un dedo, se comería el deslizamiento de
/// navegación y los scrolls.
void main() {
  const tamano = Size(360, 800);

  Future<(List<String>, Finder)> montar(WidgetTester tester) async {
    final hechos = <String>[];
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestoDeDosDedos(
            alDeslizarAbajo: () => hechos.add('abajo'),
            alDeslizarArriba: () => hechos.add('arriba'),
            alDeslizarIzquierda: () => hechos.add('izquierda'),
            alDeslizarDerecha: () => hechos.add('derecha'),
            child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
          ),
        ),
      ),
    );
    return (hechos, find.byType(GestoDeDosDedos));
  }

  /// Arrastra [dedos] punteros [dy] píxeles en vertical y [dx] en horizontal.
  Future<void> arrastrar(
    WidgetTester tester, {
    required int dedos,
    double dy = 0,
    double dx = 0,
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

  testWidgets('dos dedos hacia abajo', (tester) async {
    final (hechos, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dy: 120);
    expect(hechos, ['abajo']);
  });

  testWidgets('dos dedos hacia arriba', (tester) async {
    final (hechos, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dy: -120);
    expect(hechos, ['arriba']);
  });

  testWidgets('UN dedo no dispara: eso es navegar', (tester) async {
    final (hechos, _) = await montar(tester);
    await arrastrar(tester, dedos: 1, dy: 200);
    expect(hechos, isEmpty, reason: 'con un dedo se navega y se scrollea, no se acciona');
  });

  testWidgets('un recorrido corto no dispara', (tester) async {
    // Apoyar dos dedos y reacomodar el agarre mueve unos píxeles; eso no puede
    // abrir un panel.
    final (hechos, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dy: 20);
    expect(hechos, isEmpty);
  });

  testWidgets('dispara UNA vez por gesto, no en cada frame', (tester) async {
    final (hechos, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dy: 400);
    expect(hechos, ['abajo']);
  });

  testWidgets('sin acción en un sentido, ese sentido no hace nada', (tester) async {
    // Es como se evita que repetir el gesto cierre lo que acaba de abrir: la
    // pantalla pasa `null` en el sentido que no corresponde.
    final hechos = <String>[];
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestoDeDosDedos(
            alDeslizarAbajo: () => hechos.add('abajo'),
            child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
          ),
        ),
      ),
    );

    await arrastrar(tester, dedos: 2, dy: -200);
    expect(hechos, isEmpty);

    await arrastrar(tester, dedos: 2, dy: 200);
    expect(hechos, ['abajo']);
  });

  testWidgets('lo que ya escucha un toque lo sigue recibiendo', (tester) async {
    var toques = 0;
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestoDeDosDedos(
            alDeslizarAbajo: () {},
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

  testWidgets('dos dedos de lado', (tester) async {
    final (izq, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dx: -120);
    expect(izq, ['izquierda']);

    final (der, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dx: 120);
    expect(der, ['derecha']);
  });

  testWidgets('manda el eje dominante, no el primero que cruza', (tester) async {
    // Nadie arrastra dos dedos perfectamente rectos. Sin decidir por el eje
    // dominante, un gesto lateral con algo de caída dispararía la acción
    // vertical —o las dos.
    final (lateral, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dx: -160, dy: 40);
    expect(lateral, ['izquierda']);

    final (vertical, _) = await montar(tester);
    await arrastrar(tester, dedos: 2, dx: 40, dy: 160);
    expect(vertical, ['abajo']);
  });
}
