import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/core/ui/bento_dialogo.dart';

/// Los diálogos acostados: acciones AL COSTADO y sin scroll.
///
/// Acostado el alto es el recurso escaso. Un diálogo que manda sus botones
/// debajo desborda —el formulario de producto lo hizo por 95 px— y uno que los
/// mete en un scroll pide un gesto de más justo cuando hay cola.
void main() {
  const acostado = Size(800, 360);
  const dePie = Size(360, 800);

  Future<void> montarDialogo(WidgetTester tester, Size tamano, Widget dialogo) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBentoTheme(AcentoTinte.oro),
        home: Scaffold(body: dialogo),
      ),
    );
    await tester.pump();
  }

  Widget conCuatroBotones(BuildContext context) => BentoDialogo(
    titulo: const Text('Editar producto'),
    contenido: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(decoration: InputDecoration(labelText: 'Nombre')),
        TextField(decoration: InputDecoration(labelText: 'Precio base (₡)')),
        TextField(decoration: InputDecoration(labelText: 'Categoría')),
      ],
    ),
    acciones: BentoAcciones(
      izquierda: [
        TextButton(onPressed: () {}, child: const Text('Reactivar')),
        TextButton(onPressed: () {}, child: const Text('Eliminar')),
      ],
      derecha: [
        TextButton(onPressed: () {}, child: const Text('Cancelar')),
        FilledButton(onPressed: () {}, child: const Text('Guardar')),
      ],
    ),
  );

  testWidgets('acostado las acciones van al costado del contenido', (tester) async {
    await montarDialogo(tester, acostado, Builder(builder: conCuatroBotones));

    expect(tester.takeException(), isNull);
    // Al COSTADO: los cuatro botones arrancan a la derecha de donde termina el
    // primer campo. Debajo sería lo que no entra.
    final campo = tester.getRect(find.byType(TextField).first);
    for (final etiqueta in ['Reactivar', 'Eliminar', 'Cancelar', 'Guardar']) {
      expect(
        tester.getRect(find.text(etiqueta)).left,
        greaterThan(campo.right),
        reason: '"$etiqueta" no está al costado del formulario',
      );
    }
  });

  testWidgets('de pie las acciones vuelven abajo, en dos columnas', (tester) async {
    await montarDialogo(tester, dePie, Builder(builder: conCuatroBotones));

    expect(tester.takeException(), isNull);
    final campo = tester.getRect(find.byType(TextField).first);
    expect(tester.getRect(find.text('Guardar')).top, greaterThan(campo.top));
    // Las dos columnas se sostienen: lo que le pasa al producto a la izquierda,
    // lo que le pasa al formulario a la derecha. Apilarlos los alineaba a todos
    // a la derecha y perdía la distinción.
    expect(
      tester.getRect(find.text('Reactivar')).left,
      lessThan(tester.getRect(find.text('Cancelar')).left),
    );
    // Y las columnas quedan a escuadra entre filas.
    expect(
      tester.getRect(find.text('Reactivar')).left,
      closeTo(tester.getRect(find.text('Eliminar')).left, 1),
    );
  });

  testWidgets('una confirmación de dos botones cabe en una fila', (tester) async {
    await montarDialogo(
      tester,
      dePie,
      Builder(
        builder: (context) => BentoDialogo(
          titulo: const Text('¿Purgar este producto?'),
          contenido: const Text('Esto lo borra de forma permanente.'),
          acciones: BentoAcciones(
            izquierda: [FilledButton(onPressed: () {}, child: const Text('Purgar'))],
            derecha: [TextButton(onPressed: () {}, child: const Text('Cancelar'))],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text('Purgar')).top,
      closeTo(tester.getRect(find.text('Cancelar')).top, 1),
      reason: 'una confirmación de dos botones no tiene por qué apilarlos',
    );
  });

  // El overlay de cobro rápido no se prueba acá: montar Ventana 1 en un
  // `testWidgets` deja la bandeja cargando para siempre —la base override no
  // llega a resolverse— y forzarlo probaría el arnés, no la pantalla. Su
  // disposición acostada se verifica en el aparato (scripts/reinstalar.sh).
}
