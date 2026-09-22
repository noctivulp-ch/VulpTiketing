import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/variante_model.dart';
import 'package:vulp_tiketing/features/venta/ui/cobro_rapido_overlay.dart';
import 'package:vulp_tiketing/features/venta/ui/elegir_variante.dart';
import 'package:vulp_tiketing/features/venta/venta_en_curso_notifier.dart';

/// Las variantes en las pantallas de venta (0039).
///
/// Cada producto con variantes tiene UNA por defecto (la marcada en el
/// formulario, o la primera): es la que se cobra de un toque, y su precio es
/// el precio base. Lo que no puede pasar es que se cobre otra cosa que la
/// marcada sin que nadie la haya tocado.
void main() {
  final cafe = Producto(
    id: 'cafe',
    nombre: 'Café de máquina',
    precioBase: 800,
    variantes: const [
      Variante(id: 'p', nombre: 'Pequeño', precio: 800, porDefecto: true),
      Variante(id: 'g', nombre: 'Grande', precio: 1200),
    ],
    updatedAt: DateTime(2026),
  );

  Future<ProviderContainer> montarOverlay(WidgetTester tester, Producto producto) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // La base nunca llega: `guardar()` se queda esperando y el carrito queda
    // como se armó, que es lo que se lee. Sin esto abriría la base real.
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) => Completer<Database>().future)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CobroRapidoOverlay(producto: producto),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  group('cobro rápido', () {
    testWidgets('con variantes, la por defecto viene marcada y se cobra de un toque', (tester) async {
      final container = await montarOverlay(tester, cafe);

      final completado = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Completado'));
      expect(completado.onPressed, isNotNull, reason: 'la por defecto ya está elegida');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Precio')).controller!.text, '800');
      expect(find.text('Pequeño · ₡800'), findsOneWidget);
      expect(find.text('Grande · ₡1200'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pequeño · ₡800')).selected, isTrue);

      await tester.tap(find.text('Completado'));
      await tester.pump();
      expect(container.read(ventaEnCursoNotifierProvider).lineas.single.variante, 'Pequeño');
    });

    testWidgets('elegir la variante pone su precio y la línea la lleva', (tester) async {
      final container = await montarOverlay(tester, cafe);

      await tester.tap(find.text('Grande · ₡1200'));
      await tester.pump();

      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Precio')).controller!.text, '1200');
      final completado = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Completado'));
      expect(completado.onPressed, isNotNull);

      // Se mira el carrito, no la base: lo que importa es qué línea se armó.
      await tester.tap(find.text('Completado'));
      await tester.pump();
      final lineas = container.read(ventaEnCursoNotifierProvider).lineas;
      expect(lineas.single.variante, 'Grande');
      expect(lineas.single.precioAplicado, 1200);
      expect(lineas.single.productoId, 'cafe');
    });

    testWidgets('sin variantes no aparece el selector y se cobra como siempre', (tester) async {
      final casado = Producto(id: 'c', nombre: 'Casado', precioBase: 3000, updatedAt: DateTime(2026));
      await montarOverlay(tester, casado);

      expect(find.byType(SelectorDeVariante), findsNothing);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Precio')).controller!.text, '3000');
      final completado = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Completado'));
      expect(completado.onPressed, isNotNull);
    });
  });

  group('el precio que se muestra', () {
    test('con variantes es el de la por defecto (el precio base); sin ellas, el base', () {
      expect(precioParaMostrar(cafe), '₡800');
      final casado = Producto(id: 'c', nombre: 'Casado', precioBase: 3000, updatedAt: DateTime(2026));
      expect(precioParaMostrar(casado), '₡3000');
      expect(precioParaMostrar(casado, decimales: 2), '₡3000.00');
    });
  });

  group('la variante por defecto', () {
    test('es la marcada, o la primera si ninguna lo dice', () {
      expect(cafe.variantePorDefecto!.id, 'p');
      final sinMarca = Producto(
        id: 'x',
        nombre: 'X',
        precioBase: 1,
        variantes: const [Variante(id: 'a', nombre: 'A', precio: 1), Variante(id: 'b', nombre: 'B', precio: 2)],
        updatedAt: DateTime(2026),
      );
      expect(sinMarca.variantePorDefecto!.id, 'a');
      final casado = Producto(id: 'c', nombre: 'Casado', precioBase: 3000, updatedAt: DateTime(2026));
      expect(casado.variantePorDefecto, isNull);
    });

    test('viaja en el JSON solo cuando es verdadera', () {
      final json = variantesAColumna(cafe.variantes)!;
      expect(json, contains('"porDefecto":true'));
      expect('porDefecto'.allMatches(json), hasLength(1));
      expect(variantesDeColumna(json).map((v) => v.porDefecto), [true, false]);
    });
  });

  group('el selector del panel', () {
    testWidgets('ofrece una opción por variante y devuelve la tocada', (tester) async {
      Variante? elegida;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => elegida = await elegirVariante(context, cafe),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Café de máquina'), findsOneWidget);
      expect(find.text('Pequeño'), findsOneWidget);
      expect(find.text('Grande'), findsOneWidget);

      await tester.tap(find.text('Grande'));
      await tester.pumpAndSettle();
      expect(elegida?.id, 'g');
    });

    testWidgets('cancelar no devuelve nada', (tester) async {
      Variante? elegida = cafe.variantes.first;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => elegida = await elegirVariante(context, cafe),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(elegida, isNull);
    });
  });
}
