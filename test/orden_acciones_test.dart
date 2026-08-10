import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/ui/bento_dialogo.dart';

/// La acción que confirma va a la DERECHA, y Cancelar a su izquierda.
///
/// No es estética: lo pidió el dueño porque para guardar se pulsa a la derecha
/// sin mirar. Estaba al revés en toda la app —la acción a la izquierda, Cancelar a
/// la derecha— y en "crear categoría al vuelo" eso significa pulsar Cancelar
/// creyendo guardar. Lo encontró usándola.
///
/// Se comprueba con la geometría real, no leyendo el código: lo que importa es
/// dónde acaba el botón en la pantalla. Es una convención que se rompe sola —al
/// agregar un botón, lo natural es ponerlo donde quepa— y esta prueba es lo que
/// avisa.
void main() {
  Future<void> montar(WidgetTester tester, BentoAcciones acciones) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(AcentoTinte.oro, brightness: Brightness.dark),
        home: Scaffold(
          body: Center(child: SizedBox(width: 320, child: acciones)),
        ),
      ),
    );
    await tester.pump();
  }

  /// Que [confirma] esté a la derecha de [cancela].
  void esperarOrden(WidgetTester tester, String confirma, String cancela) {
    final xConfirma = tester.getCenter(find.text(confirma)).dx;
    final xCancela = tester.getCenter(find.text(cancela)).dx;
    expect(
      xConfirma,
      greaterThan(xCancela),
      reason: '"$confirma" tiene que quedar a la derecha de "$cancela"',
    );
  }

  group('la columna derecha es la de confirmar', () {
    testWidgets('con una acción y un cancelar, la acción va a la derecha', (tester) async {
      await montar(
        tester,
        BentoAcciones(
          izquierda: [TextButton(onPressed: () {}, child: const Text('Cancelar'))],
          derecha: [FilledButton(onPressed: () {}, child: const Text('Guardar'))],
        ),
      );

      esperarOrden(tester, 'Guardar', 'Cancelar');
    });

    testWidgets('van en la MISMA fila, no apilados', (tester) async {
      // Apilados en una columna era el otro fallo que vio el dueño: el formulario
      // de producto ponía Cancelar encima de Guardar, las dos a la derecha.
      await montar(
        tester,
        BentoAcciones(
          izquierda: [TextButton(onPressed: () {}, child: const Text('Cancelar'))],
          derecha: [FilledButton(onPressed: () {}, child: const Text('Guardar'))],
        ),
      );

      expect(tester.getCenter(find.text('Guardar')).dy, tester.getCenter(find.text('Cancelar')).dy);
    });

    testWidgets('con acciones extra, siguen en la izquierda y debajo', (tester) async {
      // Es el formulario de un producto fuera de la carta. Lo destructivo queda
      // lejos del sitio al que va el pulgar a guardar.
      await montar(
        tester,
        BentoAcciones(
          izquierda: [
            TextButton(onPressed: () {}, child: const Text('Cancelar')),
            TextButton(onPressed: () {}, child: const Text('Reactivar')),
            TextButton(onPressed: () {}, child: const Text('Eliminar')),
          ],
          derecha: [FilledButton(onPressed: () {}, child: const Text('Guardar'))],
        ),
      );

      esperarOrden(tester, 'Guardar', 'Cancelar');
      esperarOrden(tester, 'Guardar', 'Eliminar');
      expect(
        tester.getCenter(find.text('Eliminar')).dy,
        greaterThan(tester.getCenter(find.text('Guardar')).dy),
        reason: 'lo destructivo va debajo, no a la altura del botón de guardar',
      );
    });

    testWidgets('con dos confirmaciones, la segura queda abajo a la derecha', (tester) async {
      // El diálogo de importar un catálogo: Fusionar es la opción segura y la que
      // se pulsa sin mirar; Reemplazar conviene leerlo antes de tocar.
      await montar(
        tester,
        BentoAcciones(
          izquierda: [TextButton(onPressed: () {}, child: const Text('Cancelar'))],
          derecha: [
            TextButton(onPressed: () {}, child: const Text('Reemplazar')),
            FilledButton(onPressed: () {}, child: const Text('Fusionar')),
          ],
        ),
      );

      esperarOrden(tester, 'Fusionar', 'Cancelar');
      expect(
        tester.getCenter(find.text('Fusionar')).dy,
        greaterThan(tester.getCenter(find.text('Reemplazar')).dy),
      );
    });
  });

  testWidgets('un diálogo con solo salida la deja a la derecha', (tester) async {
    // Sin nada que confirmar no hay confusión posible, y la derecha es donde
    // llega el dedo.
    await montar(
      tester,
      BentoAcciones(
        derecha: [TextButton(onPressed: () {}, child: const Text('Cancelar'))],
      ),
    );

    final x = tester.getCenter(find.text('Cancelar')).dx;
    expect(x, greaterThan(320 / 2), reason: 'la única acción va en la mitad derecha');
  });
}
