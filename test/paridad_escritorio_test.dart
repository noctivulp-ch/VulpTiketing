import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/nav/atajos_escritorio.dart';
import 'package:vulp_tiketing/core/nav/gesto_navegacion.dart';

/// En escritorio se puede hacer lo mismo que en el teléfono.
///
/// Cambiar de ventana, abrir el panel de productos o exportar un reporte son
/// gestos en el aparato. En escritorio no hay dedos, y hasta acá todo eso solo
/// se podía con el ratón — exportar incluso escondido en un "mantener
/// presionado". Quien trabaja con teclado hacía el doble de camino.
void main() {
  Future<List<int>> montarAtajos(WidgetTester tester, {int indice = 2}) async {
    final cambios = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AtajosDeVentana(
            indice: indice,
            cantidad: 5,
            onCambio: cambios.add,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    return cambios;
  }

  Future<void> teclear(
    WidgetTester tester,
    LogicalKeyboardKey tecla, {
    bool control = false,
    bool shift = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(tecla);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
  }

  group('el teclado cambia de ventana', () {
    testWidgets('Ctrl+1..5 va directo', (tester) async {
      final cambios = await montarAtajos(tester);

      await teclear(tester, LogicalKeyboardKey.digit1, control: true);
      await teclear(tester, LogicalKeyboardKey.digit5, control: true);

      expect(cambios, [0, 4], reason: 'lo más rápido cuando ya se sabe a dónde se va');
    });

    testWidgets('Ctrl+Tab avanza y con Shift retrocede', (tester) async {
      final cambios = await montarAtajos(tester);

      await teclear(tester, LogicalKeyboardKey.tab, control: true);
      expect(cambios, [3]);

      await teclear(tester, LogicalKeyboardKey.tab, control: true, shift: true);
      expect(cambios, [3, 1]);
    });

    testWidgets('Ctrl+flechas hace lo mismo que el gesto', (tester) async {
      final cambios = await montarAtajos(tester);

      await teclear(tester, LogicalKeyboardKey.arrowRight, control: true);
      await teclear(tester, LogicalKeyboardKey.arrowLeft, control: true);

      expect(cambios, [3, 1]);
    });

    testWidgets('en los extremos no da la vuelta, igual que el gesto', (tester) async {
      final primera = await montarAtajos(tester, indice: 0);
      await teclear(tester, LogicalKeyboardKey.arrowLeft, control: true);
      expect(primera, isEmpty);

      final ultima = await montarAtajos(tester, indice: 4);
      await teclear(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(ultima, isEmpty);
    });

    testWidgets('las flechas SIN Ctrl no navegan: son de los campos', (tester) async {
      final cambios = await montarAtajos(tester);

      await teclear(tester, LogicalKeyboardKey.arrowRight);

      expect(cambios, isEmpty);
    });
  });

  group('el touchpad cambia de ventana', () {
    Future<List<int>> montarGesto(WidgetTester tester, {int indice = 2}) async {
      final cambios = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavegacionPorGesto(
              indice: indice,
              cantidad: 5,
              onCambio: cambios.add,
              child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
            ),
          ),
        ),
      );
      await tester.pump();
      return cambios;
    }

    /// Un gesto de trackpad llega en decenas de eventos diminutos, no en uno.
    Future<void> rodar(WidgetTester tester, Offset porEvento, {int veces = 12}) async {
      final centro = tester.getCenter(find.byType(NavegacionPorGesto));
      final puntero = TestPointer(1, PointerDeviceKind.trackpad);
      // El puntero tiene que "estar" en la pantalla antes de mandar señales.
      await tester.sendEventToBinding(puntero.hover(centro));
      for (var i = 0; i < veces; i++) {
        await tester.sendEventToBinding(puntero.scroll(porEvento));
      }
      await tester.pump();
    }

    testWidgets('dos dedos en horizontal pasan de ventana', (tester) async {
      // En un trackpad no existe arrastrar con un dedo sin apretar —eso mueve el
      // cursor—, así que el gesto de moverse es el de dos.
      final cambios = await montarGesto(tester);

      await rodar(tester, const Offset(15, 0));

      expect(cambios, [3], reason: 'a la izquierda es la siguiente, igual que con el dedo');
    });

    testWidgets('y hacia el otro lado, la anterior', (tester) async {
      final cambios = await montarGesto(tester);
      await rodar(tester, const Offset(-15, 0));
      expect(cambios, [1]);
    });

    testWidgets('el scroll VERTICAL no se toca: es de las listas', (tester) async {
      // Robárselo a las listas sería cambiar un atajo por un estorbo.
      final cambios = await montarGesto(tester);

      await rodar(tester, const Offset(0, 20), veces: 30);

      expect(cambios, isEmpty);
    });

    testWidgets('un roce diagonal mientras se scrollea no cambia nada', (tester) async {
      // Un trackpad manda algo de ruido en el otro eje casi siempre.
      final cambios = await montarGesto(tester);

      await rodar(tester, const Offset(2, 20), veces: 30);

      expect(cambios, isEmpty);
    });

    testWidgets('en los extremos tampoco da la vuelta', (tester) async {
      final cambios = await montarGesto(tester, indice: 4);
      await rodar(tester, const Offset(15, 0));
      expect(cambios, isEmpty);
    });
  });
}
