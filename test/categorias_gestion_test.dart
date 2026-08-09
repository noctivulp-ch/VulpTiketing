import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/producto/categoria_model.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_query_provider.dart';
import 'package:vulp_tiketing/features/producto/ui/categorias_panel.dart';

/// Las categorías se pueden crear, renombrar y sacar de la carta **desde la
/// app**.
///
/// El usuario lo encontró usándola: solo se podían crear, y desde el `+` del
/// formulario de producto. Para arreglar una mal escrita había que editar el
/// archivo del catálogo y volver a importarlo. `CategoriaNotifier` ya tenía
/// `actualizar` y `descontinuar` desde el principio — era un hueco de interfaz,
/// no de lógica, y por eso ninguna prueba de datos lo veía.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vulp-categorias');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await db.insert('categoria', {
      'id': 'cat-arroz',
      'nombre': 'Arroces',
      'updated_at': DateTime(2026).toIso8601String(),
    });
    await db.insert('categoria', {
      'id': 'cat-vacia',
      'nombre': 'Postres',
      'updated_at': DateTime(2026).toIso8601String(),
    });
    for (var i = 0; i < 3; i++) {
      await db.insert('producto', {
        'id': 'p$i',
        'nombre': 'Arroz $i',
        'categoria_id': 'cat-arroz',
        'precio_base': 3000.0,
        'updated_at': DateTime(2026).toIso8601String(),
      });
    }
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
    addTearDown(c.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildBentoTheme(AcentoTinte.oro),
          home: const Scaffold(body: SingleChildScrollView(child: PanelCategorias())),
        ),
      ),
    );
    await tester.pump();
    // Dos vueltas: la lista de categorías y el conteo de productos son dos
    // consultas distintas, y la segunda solo arranca cuando la primera ya
    // construyó el panel.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(seconds: 1));
    }
    return c;
  }

  testWidgets('lista las categorías con cuántos productos tiene cada una', (tester) async {
    // El número es lo que permite decidir si se puede sacar una sin romper nada.
    await montar(tester);

    expect(find.text('Arroces'), findsOneWidget);
    expect(find.text('Postres'), findsOneWidget);
    expect(find.text('3 productos'), findsOneWidget);
    expect(find.text('Sin productos'), findsOneWidget);
  });

  testWidgets('crear una categoría la agrega a la lista', (tester) async {
    final c = await montar(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Nueva categoría'), 'Bebidas');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));

    final nombres = (c.read(categoriaNotifierProvider).valueOrNull ?? []).map((x) => x.nombre);
    expect(nombres, contains('Bebidas'));
  });

  testWidgets('un nombre repetido se rechaza, sin importar mayúsculas', (tester) async {
    // Dos categorías que se llaman igual no rompen la base —cada una tiene su
    // id— pero sí la pantalla: no se sabe en cuál se está poniendo el producto.
    final c = await montar(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Nueva categoría'), '  arroces ');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));

    expect(c.read(categoriaNotifierProvider).valueOrNull, hasLength(2));
  });

  testWidgets('renombrar NO mueve los productos de sitio', (tester) async {
    // Lo que importa del renombrado: los productos apuntan al id, no al nombre.
    // Si se movieran, renombrar sería en la práctica un borrado con otro nombre.
    final c = await montar(tester);

    await tester.tap(find.text('Arroces'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Arroz');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));

    final categorias = c.read(categoriaNotifierProvider).valueOrNull ?? [];
    expect(categorias.firstWhere((x) => x.id == 'cat-arroz').nombre, 'Arroz');

    final conSuCategoria = await tester.runAsync(
      () => db.query('producto', where: 'categoria_id = ?', whereArgs: ['cat-arroz']),
    );
    expect(
      conSuCategoria,
      hasLength(3),
      reason: 'los productos se quedaron sin su categoría al renombrarla',
    );
  });

  testWidgets('sacar una categoría avisa cuántos productos quedan sin ella', (tester) async {
    // Un "¿estás seguro?" sin el número no aporta nada que el usuario no
    // supiera ya al tocar el botón.
    await montar(tester);

    await tester.tap(find.byTooltip('Sacar de la carta').first);
    await tester.pumpAndSettle();

    // Se busca la frase del diálogo, no "3 productos" a secas: eso también lo
    // dice la fila de la lista que quedó debajo.
    expect(find.textContaining('Hay 3 productos'), findsOneWidget);
    expect(find.textContaining('No se borran'), findsOneWidget);
  });

  testWidgets('sacarla no borra sus productos', (tester) async {
    // La consecuencia que hay que garantizar: la categoría se va, el inventario
    // se queda. Borrar productos al sacar una categoría sería una pérdida de
    // datos disparada por un cambio de organización.
    final c = await montar(tester);

    await tester.tap(find.byTooltip('Sacar de la carta').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sacar'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));

    expect(
      (c.read(categoriaNotifierProvider).valueOrNull ?? []).map((x) => x.id),
      isNot(contains('cat-arroz')),
    );
    // Se pregunta a la BASE, no al provider: acabamos de invalidarlo y esperar
    // su `future` justo después deja la prueba colgada hasta el timeout. Y
    // además es la comprobación más honesta — lo que importa es que las filas
    // sigan ahí, no que un notifier las recuerde.
    final filas = await tester.runAsync(() => db.query('producto'));
    expect(filas, hasLength(3), reason: 'los productos se borraron con la categoría');
  });

  group('el icono elegido a mano', () {
    // El acierto por nombre está bien y sigue siendo el defecto, pero sale de
    // una tabla de palabras: una categoría que el negocio llame "Especiales" o
    // "Lo de la casa" no tiene de dónde adivinarse. Una categoría con la cara
    // equivocada es peor que una sin cara, porque dice algo que no es.

    testWidgets('el elegido gana al que saldría del nombre', (tester) async {
      final c = await montar(tester);

      await tester.runAsync(
        () => c
            .read(categoriaNotifierProvider.notifier)
            .actualizar(
              Categoria(
                id: 'cat-arroz',
                nombre: 'Arroces',
                icono: 'postre',
                updatedAt: DateTime.now(),
              ),
            ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(c.read(iconosDeCategoriaProvider)['cat-arroz'], 'postre');
    });

    testWidgets('sin elegir nada sigue mandando el nombre', (tester) async {
      // Que la columna nueva no cambie el comportamiento de las categorías que
      // nadie tocó, que son casi todas.
      final c = await montar(tester);

      expect(c.read(iconosDeCategoriaProvider)['cat-arroz'], 'casado');
      expect(c.read(iconosDeCategoriaProvider)['cat-vacia'], 'postre');
    });

    testWidgets('volver al automático deshace la elección', (tester) async {
      // Es la salida de un cambio del que uno se arrepiente, y por eso el
      // diálogo distingue "Automático" de "Cancelar".
      final c = await montar(tester);
      final notifier = c.read(categoriaNotifierProvider.notifier);

      await tester.runAsync(
        () => notifier.actualizar(
          Categoria(id: 'cat-arroz', nombre: 'Arroces', icono: 'postre', updatedAt: DateTime.now()),
        ),
      );
      await tester.runAsync(
        () => notifier.actualizar(
          Categoria(id: 'cat-arroz', nombre: 'Arroces', updatedAt: DateTime.now()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(c.read(iconosDeCategoriaProvider)['cat-arroz'], 'casado');
    });

    testWidgets('renombrar no borra el icono elegido', (tester) async {
      // Si se perdiera al renombrar, cada corrección de una errata desharía la
      // elección sin avisar.
      final c = await montar(tester);
      await tester.runAsync(
        () => c
            .read(categoriaNotifierProvider.notifier)
            .actualizar(
              Categoria(
                id: 'cat-arroz',
                nombre: 'Arroces',
                icono: 'postre',
                updatedAt: DateTime.now(),
              ),
            ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Arroces'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Arroz');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(seconds: 1));

      expect(c.read(iconosDeCategoriaProvider)['cat-arroz'], 'postre');
    });

    testWidgets('el icono de la fila se toca y abre el selector', (tester) async {
      await montar(tester);

      await tester.tap(find.byTooltip('Elegir icono').first);
      await tester.pumpAndSettle();

      expect(find.text('Icono de la categoría'), findsOneWidget);
      // Y el automático se distingue, para que "volver al automático" diga a
      // qué se vuelve.
      expect(find.byTooltip('Casado (el automático)'), findsOneWidget);
    });
  });
}
