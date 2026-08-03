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
import 'package:vulp_tiketing/core/theme/bento_icono_producto.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
import 'package:vulp_tiketing/features/producto/ui/imagen_del_banco_vista.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/ui/panel_venta_screen.dart';
import 'package:vulp_tiketing/features/venta/ui/venta_rapida_screen.dart';
import 'package:vulp_tiketing/features/venta/venta_en_curso_notifier.dart';

/// La imagen de un producto no puede comerse el texto que hay que leer.
///
/// El usuario lo encontró en el aparato, y en dos sitios a la vez: en Venta
/// Rápida y en el carrito de Venta Completa, un producto con imagen asignada
/// mostraba un icono de "hay una imagen aquí" —el mismo para todos— **y además**
/// le quitaba sitio al nombre. Dos fallos encadenados: la imagen elegida nunca
/// llegaba a pintarse, y el hueco que ocupaba salía del nombre.
///
/// Ninguna prueba lo veía: `layout_responsive_test` siembra productos **sin**
/// imagen, así que el hueco no se reservaba nunca y las dos pantallas pasaban.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  /// Nombres cortos a propósito: si con "Café" el texto no entra, es la imagen
  /// quien se lo comió y no la longitud del nombre.
  const nombres = ['Café', 'Casado', 'Batido', 'Sopa'];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vulp-imagen');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await aplicarEsquemaLibro(db);
    await db.insert('categoria', {
      'id': 'cat',
      'nombre': 'General',
      'updated_at': DateTime(2026).toIso8601String(),
    });
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Siembra DENTRO de `runAsync`: los `pump` mueven un reloj falso y una
  /// escritura a SQLite es I/O de verdad, así que un `insert` lanzado desde el
  /// cuerpo de un `testWidgets` no avanza nunca y el caso muere por timeout —
  /// tres minutos de espera sin un solo mensaje que diga por qué.
  Future<void> sembrar(WidgetTester tester, {required bool conImagen}) {
    const claves = ['cafe', 'casado', 'batido', 'sopa'];
    return tester.runAsync(() async {
      for (var i = 0; i < nombres.length; i++) {
        await db.insert('producto', {
          'id': 'p$i',
          'nombre': nombres[i],
          'categoria_id': 'cat',
          'precio_base': 1500.0 + i * 100,
          if (conImagen) 'imagen': 'ico:${claves[i]}',
          'updated_at': DateTime(2026).toIso8601String(),
        });
      }
    });
  }

  Future<ProviderContainer> montar(WidgetTester tester, Widget pantalla, Size tamano) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final contenedor = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        libroVentasServiceProvider.overrideWith(
          (ref) async => LibroVentasService(directorio: dir.path),
        ),
        // Sin este doble la pantalla se queda esperando al llavero: el canal
        // nativo de `flutter_secure_storage` no se puede interceptar desde una
        // prueba, así que la sesión nunca resuelve y el test muere por timeout.
        sesionNotifierProvider.overrideWith(() => _SesionFija(Rol.registradora)),
      ],
    );
    addTearDown(contenedor.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: MaterialApp(theme: buildBentoTheme(AcentoTinte.oro), home: pantalla),
      ),
    );
    // Las consultas a SQLite son I/O de verdad y no avanzan con el reloj falso
    // de `pump`; sin `runAsync` la pantalla se queda en el indicador de carga.
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    return contenedor;
  }

  /// Ningún nombre de producto quedó recortado por falta de sitio.
  ///
  /// Se miran los nombres y no todo el texto de la pantalla: el marcador del
  /// buscador ("Buscar producto o categoría…") se elide por su cuenta a 360 dp
  /// y siempre lo hizo — es un marcador, no un dato, y darlo por fallo dejaría
  /// la prueba en rojo por algo que no tiene que ver con la imagen.
  void nombresEnteros(WidgetTester tester, {required String donde}) {
    for (final elemento in find.byType(RichText).evaluate()) {
      final parrafo = elemento.renderObject! as RenderParagraph;
      final texto = parrafo.text.toPlainText();
      if (!nombres.contains(texto)) continue;
      expect(
        parrafo.didExceedMaxLines,
        isFalse,
        reason: '$donde: "$texto" quedó cortado por la imagen',
      );
    }
  }

  const tamanos = <String, Size>{
    'de pie 360x800': Size(360, 800),
    'acostado 800x360': Size(800, 360),
    'tablet 800x1280': Size(800, 1280),
    'escritorio 1440x900': Size(1440, 900),
  };

  group('Venta Rápida', () {
    for (final tamano in tamanos.entries) {
      testWidgets('la imagen elegida se pinta y el texto entero cabe (${tamano.key})', (
        tester,
      ) async {
        await sembrar(tester, conImagen: true);
        await montar(tester, const VentaRapidaScreen(), tamano.value);

        // Que se pinte la imagen ELEGIDA. Antes salía un `Icons.image_outlined`
        // fijo: el mismo dibujo para todos los productos, o sea un cartel de
        // "hay una imagen" en vez de la imagen.
        expect(find.byType(ImagenDelBancoVista), findsWidgets);
        expect(find.byIcon(iconoDeProductoDe('cafe').icono), findsWidgets);
        expect(find.byIcon(Icons.image_outlined), findsNothing);

        for (final nombre in nombres) {
          expect(find.text(nombre), findsWidgets, reason: 'falta "$nombre" en ${tamano.key}');
        }
        nombresEnteros(tester, donde: 'Venta Rápida ${tamano.key}');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('sin imagen elegida la celda igual tiene cara: la de la categoría', (tester) async {
      // Todas las celdas llevan dibujo, no solo las que tienen imagen elegida:
      // una cuadrícula donde unas lo tienen y otras no se lee peor que una
      // donde todas lo tienen — las filas dejan de alinearse sin que eso
      // signifique nada.
      await sembrar(tester, conImagen: false);
      await montar(tester, const VentaRapidaScreen(), const Size(360, 800));

      expect(find.byType(ImagenDelBancoVista), findsWidgets);
      for (final nombre in nombres) {
        expect(find.text(nombre), findsWidgets);
      }
      nombresEnteros(tester, donde: 'Venta Rápida sin imagen elegida');
      expect(tester.takeException(), isNull);
    });
  });

  group('el carrito de Venta Completa', () {
    Future<void> conLineas(WidgetTester tester, {required bool conImagen}) async {
      await sembrar(tester, conImagen: conImagen);
      // Angosto a propósito: es el carrito con el panel de productos abierto,
      // donde el usuario vio el problema.
      final contenedor = await montar(tester, const PanelVentaScreen(), const Size(360, 800));
      final carrito = contenedor.read(ventaEnCursoNotifierProvider.notifier);
      for (var i = 0; i < nombres.length; i++) {
        carrito.agregarLineaDeCatalogo(productoId: 'p$i', precioAplicado: 1500.0 + i * 100);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('un producto con imagen la muestra, y el nombre entero cabe', (tester) async {
      await conLineas(tester, conImagen: true);

      for (final nombre in nombres) {
        expect(find.text(nombre), findsWidgets, reason: 'falta "$nombre" en el carrito');
      }
      expect(find.byType(ImagenDelBancoVista), findsWidgets);
      expect(find.byIcon(Icons.image_outlined), findsNothing);
      nombresEnteros(tester, donde: 'carrito con imagen');
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin imagen elegida la miniatura es la de la categoría', (tester) async {
      await conLineas(tester, conImagen: false);

      expect(find.byType(ImagenDelBancoVista), findsWidgets);
      for (final nombre in nombres) {
        expect(find.text(nombre), findsWidgets);
      }
      // Lo que importa en el carrito angosto: el nombre sigue entero con la
      // miniatura puesta.
      nombresEnteros(tester, donde: 'carrito sin imagen elegida');
      expect(tester.takeException(), isNull);
    });

    testWidgets('la línea libre conserva su lápiz aunque no tenga imagen', (tester) async {
      // El lápiz es lo que la distingue de un producto de la carta: es un dato,
      // no un relleno, así que no se va con el resto de los huecos vacíos.
      await sembrar(tester, conImagen: false);
      final contenedor = await montar(tester, const PanelVentaScreen(), const Size(360, 800));
      contenedor
          .read(ventaEnCursoNotifierProvider.notifier)
          .agregarLineaLibre(nombreLibre: 'Encargo', precio: 2500);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Encargo'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
    });
  });
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this.rol);

  final Rol rol;

  @override
  Rol? build() => rol;
}
