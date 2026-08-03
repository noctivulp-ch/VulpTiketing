import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/producto_query_provider.dart';
import 'package:vulp_tiketing/features/producto/ui/lista_productos_agrupada.dart';
import 'package:vulp_tiketing/features/producto/ui/producto_crud_screen.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/ui/panel_venta_screen.dart';

/// Un nombre largo se muestra **entero**, tomando las líneas que haga falta.
///
/// Las dos listas de producto —el catálogo de Inventario y el panel de agregar
/// de Venta— daban a cada fila el alto de una sola línea, así que el nombre se
/// elidía. En esta carta eso es peor que un recorte cualquiera, porque los
/// nombres se distinguen justo al final: "Arroz con pollo, tipo chino (entero)"
/// y "…(medio)" quedaban los dos en "Arroz con pollo, tipo chi…" —
/// indistinguibles en la pantalla desde la que se elige qué cobrar.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const largo = 'Arroz con pollo, tipo chino (entero)';
  const largoHermano = 'Arroz con pollo, tipo chino (medio)';
  const corto = 'Café';

  group('cuántas líneas hacen falta', () {
    GrupoDeProductos grupoCon(List<String> nombres) => GrupoDeProductos(
      titulo: null,
      productos: [
        for (var i = 0; i < nombres.length; i++)
          Producto(id: 'p$i', nombre: nombres[i], precioBase: 1500, updatedAt: DateTime(2026)),
      ],
    );

    const estilo = TextStyle(fontSize: 16, height: 1.35);

    test('con nombres cortos se queda en una línea y no crece', () {
      // Que el arreglo no engorde las filas de una carta que no lo necesita.
      final medida = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([corto, 'Sopa', 'Tamal']),
        ],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 200,
        altoConUnaLinea: 76,
      );

      expect(medida.lineasDelNombre, 1);
      expect(medida.alto, 76);
    });

    test('un nombre largo pide más de una línea, y la fila crece con él', () {
      final medida = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([corto, largo]),
        ],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 150,
        altoConUnaLinea: 76,
      );

      expect(medida.lineasDelNombre, greaterThan(1));
      expect(medida.alto, greaterThan(76));
    });

    test('manda el más largo de TODA la lista, no el primero', () {
      // Las celdas de una cuadrícula miden todas lo mismo: si el alto saliera
      // de un producto cualquiera, el más largo desbordaría su celda.
      final conLargoAlFinal = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([corto, 'Sopa', largo]),
        ],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 150,
        altoConUnaLinea: 76,
      );
      final soloElLargo = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([largo]),
        ],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 150,
        altoConUnaLinea: 76,
      );

      expect(conLargoAlFinal.alto, soloElLargo.alto);
    });

    test('mira todos los grupos, no solo el primero', () {
      final medida = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([corto]),
          grupoCon([largo]),
        ],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 150,
        altoConUnaLinea: 76,
      );

      expect(medida.lineasDelNombre, greaterThan(1));
    });

    test('el tope se respeta: no crece sin límite', () {
      // Un nombre absurdo no puede dejar una sola fila ocupando la pantalla.
      final medida = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([List.filled(80, 'palabra').join(' ')]),
        ],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 100,
        altoConUnaLinea: 76,
        maxLineas: 3,
      );

      expect(medida.lineasDelNombre, 3);
    });

    test('con la letra grande del sistema pide más líneas', () {
      // Un alto calculado con el tamaño base volvería a cortar el nombre en un
      // teléfono con la accesibilidad subida. Ancho holgado y tope alto a
      // propósito: si los dos casos chocan contra el máximo, la prueba pasaría
      // sin comprobar nada.
      final normal = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([largo]),
        ],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 400,
        altoConUnaLinea: 76,
        maxLineas: 8,
      );
      final grande = altoDeFilaSegunNombre(
        grupos: [
          grupoCon([largo]),
        ],
        estilo: estilo,
        escala: const TextScaler.linear(1.6),
        anchoDelTexto: 400,
        altoConUnaLinea: 76,
        maxLineas: 8,
      );

      expect(grande.lineasDelNombre, greaterThan(normal.lineasDelNombre));
      expect(grande.alto, greaterThan(normal.alto));
    });

    test('una lista vacía no revienta', () {
      final medida = altoDeFilaSegunNombre(
        grupos: [grupoCon([])],
        estilo: estilo,
        escala: TextScaler.noScaling,
        anchoDelTexto: 150,
        altoConUnaLinea: 76,
      );

      expect(medida.lineasDelNombre, 1);
    });
  });

  group('en las dos pantallas de verdad', () {
    late Directory dir;
    late Database db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('vulp-nombres');
      db = await databaseFactory.openDatabase(
        p.join(dir.path, 'vulp_tiketing.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await AppDatabase.crearEsquema(db);
      await aplicarEsquemaLibro(db);
      await db.insert('categoria', {
        'id': 'cat',
        'nombre': 'Arroces',
        'updated_at': DateTime(2026).toIso8601String(),
      });
      for (final (i, nombre) in [largo, largoHermano, corto].indexed) {
        await db.insert('producto', {
          'id': 'p$i',
          'nombre': nombre,
          'categoria_id': 'cat',
          'precio_base': 1500.0 + i,
          'updated_at': DateTime(2026).toIso8601String(),
        });
      }
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<void> montar(WidgetTester tester, Widget pantalla, Size tamano) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWith((ref) async => db),
            libroVentasServiceProvider.overrideWith(
              (ref) async => LibroVentasService(directorio: dir.path),
            ),
            sesionNotifierProvider.overrideWith(() => _SesionFija(Rol.gerente)),
          ],
          child: MaterialApp(theme: buildBentoTheme(AcentoTinte.oro), home: pantalla),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    /// El nombre largo NO está limitado a una línea, y de hecho ocupa más
    /// alto que uno corto.
    ///
    /// Las dos cosas: `maxLines` demuestra la intención —nulo es "las que haga
    /// falta"— y la comparación de alturas demuestra el resultado, sin depender
    /// de cuántas líneas pida la fuente. En una prueba de widget la fuente es
    /// Ahem, donde cada glifo es un cuadrado del alto de la letra y es bastante
    /// más ancha que la de verdad, así que fijar un número de líneas sería
    /// medir la fuente de prueba y no lo que pasa en el teléfono.
    void nombreSinLimiteDeUnaLinea(WidgetTester tester, String donde) {
      final largos = find.text(largo).evaluate().followedBy(find.text(largoHermano).evaluate());
      expect(largos, isNotEmpty, reason: '$donde: no se encontró ningún nombre largo');

      for (final elemento in largos) {
        expect(
          (elemento.widget as Text).maxLines,
          isNot(1),
          reason: '$donde: el nombre sigue limitado a una sola línea',
        );
      }

      // Comparado contra SÍ MISMO en una línea —lo que mediría con ancho de
      // sobra—, no contra otro producto: en el panel la lista es perezosa y el
      // nombre corto puede no estar construido todavía, y una referencia que a
      // veces no existe convierte la prueba en un dado.
      for (final elemento in largos) {
        final parrafo = elemento.renderObject! as RenderParagraph;
        expect(
          parrafo.size.height,
          greaterThan(parrafo.getMaxIntrinsicHeight(double.infinity)),
          reason: '$donde: el nombre se dibujó en una sola línea',
        );
      }
    }

    testWidgets('el catálogo de Inventario muestra el nombre entero de pie', (tester) async {
      await montar(tester, const ProductoCrudScreen(), const Size(360, 800));

      nombreSinLimiteDeUnaLinea(tester, 'catálogo 360x800');
      expect(tester.takeException(), isNull);
    });

    testWidgets('y también en escritorio, con tres por fila', (tester) async {
      // El caso que más aprieta: la celda mide un tercio y los tres botones del
      // Gerente siguen ocupando lo mismo.
      await montar(tester, const ProductoCrudScreen(), const Size(1440, 900));

      nombreSinLimiteDeUnaLinea(tester, 'catálogo 1440x900');
      expect(tester.takeException(), isNull);
    });

    testWidgets('el panel de agregar de Venta también', (tester) async {
      await montar(tester, const PanelVentaScreen(), const Size(360, 800));
      // El panel arranca cerrado: se abre con el botón de la costura.
      await tester.tap(find.byTooltip('Agregar productos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      nombreSinLimiteDeUnaLinea(tester, 'panel de agregar');
      expect(tester.takeException(), isNull);
    });
  });
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this.rol);

  final Rol rol;

  @override
  Rol? build() => rol;
}
