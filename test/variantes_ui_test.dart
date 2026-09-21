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
/// Lo que no puede pasar: cobrar un producto con variantes SIN haber elegido
/// una. Es el error silencioso del diseño —el café grande cobrado como
/// pequeño— y la única defensa es que el botón no exista hasta que se elija.
void main() {
  final cafe = Producto(
    id: 'cafe',
    nombre: 'Café de máquina',
    precioBase: 800,
    variantes: const [
      Variante(id: 'p', nombre: 'Pequeño', precio: 800),
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
    testWidgets('con variantes, Completado está apagado hasta elegir una', (tester) async {
      await montarOverlay(tester, cafe);

      final completado = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Completado'));
      expect(completado.onPressed, isNull, reason: 'sin variante no hay qué cobrar');
      // Y el precio va vacío: el base no es el de ninguna de las dos.
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Precio')).controller!.text, '');
      expect(find.text('Pequeño · ₡800'), findsOneWidget);
      expect(find.text('Grande · ₡1200'), findsOneWidget);
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
    test('con variantes dice "desde" y el menor; sin ellas, el base', () {
      expect(precioParaMostrar(cafe), 'desde ₡800');
      final casado = Producto(id: 'c', nombre: 'Casado', precioBase: 3000, updatedAt: DateTime(2026));
      expect(precioParaMostrar(casado), '₡3000');
      expect(precioParaMostrar(casado, decimales: 2), '₡3000.00');
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
