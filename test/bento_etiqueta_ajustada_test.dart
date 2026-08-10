import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_cuadricula.dart';
import 'package:vulp_tiketing/core/ui/bento_etiqueta_ajustada.dart';

/// Una etiqueta encoge antes que partirse a mitad de palabra.
///
/// El caso real: "Optimización" en la rejilla de Configuración. El tile deja
/// ~69 dp de texto a 360 dp de ancho, la palabra no entra, y Flutter la cortaba a
/// mitad —"Optimizaci / ón"— porque partir por carácter es lo que hace cuando una
/// palabra sola es más ancha que la línea. El dueño lo decidió así: "dejar que se
/// encoja la tipografía está bien".
///
/// La otra mitad de estas pruebas es que **funcione dentro de la rejilla**. El
/// primer intento medía el ancho con un `LayoutBuilder` y reventaba la pantalla
/// entera: `BentoCuadricula` comparte el alto de cada fila con `IntrinsicHeight`,
/// y un `LayoutBuilder` no sabe dar dimensiones intrínsecas. De ahí el último
/// caso de este archivo.
void main() {
  /// Cuánto ocupa la etiqueta **pintada** en una caja de [ancho].
  ///
  /// `getRect` y no `getSize`: `FittedBox` encoge con una transformación, así que
  /// el tamaño propio del `Text` sigue siendo el grande y solo el rectángulo
  /// pintado refleja la escala. Medir el otro daba 122 dp dentro de una caja de
  /// 69 y parecía un desborde que no existía.
  Future<Size> medir(WidgetTester tester, String texto, double ancho) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: ancho,
              child: BentoEtiquetaAjustada(texto, estilo: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getRect(find.text(texto)).size;
  }

  testWidgets('lo que entra se deja tal cual', (tester) async {
    // `scaleDown` solo reduce: nunca agranda un texto que ya cabía.
    final holgado = await medir(tester, 'Tema', 300);
    final justo = await medir(tester, 'Tema', 69);

    expect(justo.width, holgado.width);
  });

  testWidgets('lo que no entra se encoge, no se parte', (tester) async {
    final ancho = 69.0;
    await medir(tester, 'Optimización', ancho);

    // Una sola línea —no partida— y dentro de la caja.
    final caja = tester.getRect(find.text('Optimización'));
    expect(caja.width, lessThanOrEqualTo(ancho + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('siempre una línea, aunque sean dos palabras', (tester) async {
    // Antes "Cerrar sesión" se repartía en dos líneas y "Optimización" se partía
    // por carácter. Con una sola línea y sin ceder, la única salida que le queda
    // a `FittedBox` es encoger — que es lo que se pidió.
    await medir(tester, 'Cerrar sesión', 69);

    final texto = tester.widget<Text>(find.text('Cerrar sesión'));
    expect(texto.maxLines, 1);
    expect(texto.softWrap, isFalse);
  });

  testWidgets('ninguna etiqueta real desborda a los anchos de la rejilla', (tester) async {
    for (final ancho in [69.0, 100.0, 160.0]) {
      for (final etiqueta in [
        'Contraseña',
        'Exportar',
        'Restaurar',
        'Catálogo',
        'Sincronizar',
        'Cerrar sesión',
        'Orden',
        'Acento',
        'Tema',
        'Categorías',
        'Optimización',
        'Sistema',
        'Acceso',
        'Acerca de',
      ]) {
        final tamano = await medir(tester, etiqueta, ancho);
        expect(tamano.width, lessThanOrEqualTo(ancho + 0.5), reason: '"$etiqueta" a $ancho dp');
        expect(tester.takeException(), isNull, reason: '"$etiqueta" a $ancho dp');
      }
    }
  });

  testWidgets('funciona dentro de la cuadrícula, que comparte alto por fila', (tester) async {
    // El fallo del primer intento: con un `LayoutBuilder` acá dentro, el
    // `IntrinsicHeight` de la cuadrícula lanzaba y la pantalla no se dibujaba.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BentoCuadricula(
            hijos: [
              for (final etiqueta in ['Optimización', 'Sistema', 'Acerca de'])
                BentoCelda(compacto: 2, medio: 2, amplio: 2, hijo: BentoEtiquetaAjustada(etiqueta)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Optimización'), findsOneWidget);
  });
}
