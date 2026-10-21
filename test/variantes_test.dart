import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/import_export/tiketdata_service.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/variante_model.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/linea_venta_model.dart';
import 'package:vulp_tiketing/features/venta/venta_en_curso_notifier.dart';

/// Las variantes de un producto (decisión 0039): JSON en `producto.variantes`
/// y el NOMBRE de la vendida en `linea_venta.variante`.
///
/// Lo que se vigila, y por qué:
///
/// - **El JSON ida y vuelta**, porque un producto que se guarda con variantes y
///   se lee sin ellas se vende al precio base — más barato — sin que nadie lo
///   note hasta el cierre.
/// - **Las dos migraciones**, sobre una base v5 y un libro viejos de verdad: es
///   la regla de `docs/versiones.md` desde que hay datos en producción.
/// - **Que un catálogo exportado por la 1.0.0 se importe tal cual.** Es el
///   archivo real de la carta, con 63 productos; si la columna nueva rompiera
///   la importación, la carta no podría cargarse en la versión nueva.
/// - **El ranking por producto Y variante**, que es para lo que existen.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const grande = Variante(id: 'g', nombre: 'Grande', precio: 1200);
  const chico = Variante(id: 'c', nombre: 'Pequeño', precio: 800);

  Producto cafe({List<Variante> variantes = const []}) => Producto(
    id: 'cafe',
    nombre: 'Café',
    precioBase: 800,
    variantes: variantes,
    updatedAt: DateTime(2026, 9, 21),
  );

  group('el JSON de la columna', () {
    test('ida y vuelta conserva id, nombre y precio', () {
      final columna = variantesAColumna([grande, chico]);
      expect(variantesDeColumna(columna), [grande, chico]);
    });

    test('sin variantes la columna es NULL, no una lista vacía', () {
      // Dos formas del mismo nada obligarían a todo lector a tratar ambas.
      expect(variantesAColumna(const []), isNull);
      expect(variantesDeColumna(null), isEmpty);
      expect(variantesDeColumna('[]'), isEmpty);
    });

    test('una columna rota no tumba la lectura del producto', () {
      // Un archivo editado a mano o un sync a medias no puede dejar la pantalla
      // de venta sin catálogo: se lee como "sin variantes".
      expect(variantesDeColumna('{"no": "es lista"}'), isEmpty);
      expect(variantesDeColumna('   '), isEmpty);
    });

    test('el producto lleva y trae sus variantes por toMap/fromMap', () {
      final leido = Producto.fromMap(cafe(variantes: [grande, chico]).toMap());
      expect(leido.variantes, [grande, chico]);
      expect(leido.tieneVariantes, isTrue);
      expect(leido.precioMinimo, 800, reason: 'el menor, para el "desde"');
      expect(Producto.fromMap(cafe().toMap()).tieneVariantes, isFalse);
    });
  });

  group('v5 → v6: la columna en producto', () {
    late Directory temporal;
    setUp(() => temporal = Directory.systemTemp.createTempSync('vulp-variantes'));
    tearDown(() => temporal.deleteSync(recursive: true));

    /// Una base tal como la dejó la 1.0.0: `producto` sin `variantes`.
    Future<Database> baseV5() async {
      final db = await databaseFactory.openDatabase(
        p.join(temporal.path, 'v5.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute(
        'CREATE TABLE producto (id TEXT PRIMARY KEY, nombre TEXT NOT NULL, imagen TEXT, '
        'categoria_id TEXT, precio_base REAL NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT);',
      );
      await db.insert('producto', {
        'id': 'casado',
        'nombre': 'Casado con filet',
        'precio_base': 3000,
        'updated_at': DateTime(2026).toIso8601String(),
      });
      return db;
    }

    test('agrega la columna y las filas de antes quedan sin variantes', () async {
      final db = await baseV5();
      await AppDatabase.agregarVariantesDeProducto(db);

      final producto = Producto.fromMap((await db.query('producto')).single);
      expect(producto.nombre, 'Casado con filet');
      expect(producto.tieneVariantes, isFalse);
      await db.close();
    });

    test('aplicarla dos veces no rompe', () async {
      final db = await baseV5();
      await AppDatabase.agregarVariantesDeProducto(db);
      await AppDatabase.agregarVariantesDeProducto(db);
      expect(await db.query('producto'), hasLength(1));
      await db.close();
    });

    test('una base nueva ya la trae', () async {
      final db = await databaseFactory.openDatabase(
        p.join(temporal.path, 'nueva.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await AppDatabase.crearEsquema(db);
      final columnas = await db.rawQuery('PRAGMA table_info(producto)');
      expect(columnas.map((c) => c['name']), contains('variantes'));
      await db.close();
    });
  });

  group('el libro de ventas gana linea_venta.variante', () {
    late Directory temporal;
    setUp(() => temporal = Directory.systemTemp.createTempSync('vulp-libro-variante'));
    tearDown(() => temporal.deleteSync(recursive: true));

    test('un libro viejo se pone al día en las DOS tablas', () async {
      // Hasta ahora la puesta al día solo sabía de `venta`; si `linea_venta`
      // se quedara atrás, guardar una venta con variante fallaría por columna
      // desconocida justo en un libro con historial.
      final viejo = await databaseFactory.openDatabase(
        p.join(temporal.path, 'libro-viejo.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await viejo.execute(
        'CREATE TABLE venta (id TEXT PRIMARY KEY, fecha_hora TEXT NOT NULL, detalle TEXT, '
        "estado TEXT NOT NULL DEFAULT 'activa', motivo_reversion TEXT, updated_at TEXT NOT NULL)",
      );
      await viejo.execute(
        'CREATE TABLE linea_venta (id TEXT PRIMARY KEY, venta_id TEXT NOT NULL, producto_id TEXT, '
        'nombre_libre TEXT, precio_aplicado REAL NOT NULL, cantidad INTEGER NOT NULL DEFAULT 1, '
        'nota TEXT, updated_at TEXT NOT NULL)',
      );
      await viejo.insert('linea_venta', {
        'id': 'l1',
        'venta_id': 'v1',
        'producto_id': 'cafe',
        'precio_aplicado': 800,
        'updated_at': DateTime(2026).toIso8601String(),
      });

      await ponerAlDiaEsquemaDeLibro(viejo);
      await ponerAlDiaEsquemaDeLibro(viejo); // repetido: se llama en cada ATTACH

      final columnas = {
        for (final c in await viejo.rawQuery('PRAGMA table_info(linea_venta)')) c['name'] as String,
      };
      expect(columnas, contains('variante'));
      final columnasVenta = {
        for (final c in await viejo.rawQuery('PRAGMA table_info(venta)')) c['name'] as String,
      };
      expect(columnasVenta, containsAll(['metodo_pago', 'referencia_pago']));
      // La línea de antes se lee como sin variante, que es lo que era.
      expect(LineaVenta.fromMap((await viejo.query('linea_venta')).single).variante, isNull);
      await viejo.close();
    });

    test('un libro nuevo ya la trae', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await aplicarEsquemaLibro(db);
      final columnas = await db.rawQuery('PRAGMA table_info(linea_venta)');
      expect(columnas.map((c) => c['name']), contains('variante'));
      await db.close();
    });
  });

  group('en la venta', () {
    test('la línea lleva el nombre de la variante y su precio, y editarla no lo pierde', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final carrito = container.read(ventaEnCursoNotifierProvider.notifier);

      carrito.agregarLineaDeCatalogo(productoId: 'cafe', precioAplicado: 1200, variante: 'Grande');
      final linea = container.read(ventaEnCursoNotifierProvider).lineas.single;
      expect(linea.variante, 'Grande');
      expect(linea.precioAplicado, 1200);
      expect(linea.describir('Café'), 'Café · Grande');

      // Cambiar la cantidad reconstruye la línea: la variante tiene que viajar.
      carrito.editarLinea(linea.id, cantidad: 3);
      expect(container.read(ventaEnCursoNotifierProvider).lineas.single.variante, 'Grande');
    });

    test('sin variante se describe solo por el nombre', () {
      final linea = LineaVenta(
        id: 'l',
        ventaId: 'v',
        productoId: 'cafe',
        precioAplicado: 800,
        updatedAt: DateTime(2026),
      );
      expect(linea.describir('Café'), 'Café');
      expect(linea.toMap()['variante'], isNull);
    });
  });

  group('en los reportes', () {
    Future<Database> abrirDb() async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await AppDatabase.crearEsquema(db);
      await aplicarEsquemaLibro(db);
      return db;
    }

    Future<void> vender(Database db, String id, String? variante, int cantidad) async {
      final fecha = DateTime(2026, 3, 10, 12);
      await db.insert('venta', {
        'id': id,
        'fecha_hora': fecha.toIso8601String(),
        'estado': 'activa',
        'updated_at': fecha.toIso8601String(),
      });
      await db.insert('linea_venta', {
        'id': 'l-$id',
        'venta_id': id,
        'producto_id': 'pollo',
        'precio_aplicado': 2300,
        'cantidad': cantidad,
        'variante': variante,
        'updated_at': fecha.toIso8601String(),
      });
    }

    test('el ranking separa las variantes de un mismo producto', () async {
      final db = await abrirDb();
      addTearDown(db.close);
      await db.insert('producto', {
        'id': 'pollo',
        'nombre': 'Pollo frito',
        'precio_base': 2300,
        'updated_at': DateTime(2026).toIso8601String(),
      });
      await vender(db, 'v1', 'Pechuga y ala', 5);
      await vender(db, 'v2', 'Cadera y muslo', 2);
      await vender(db, 'v3', null, 1); // vendido antes de que tuviera variantes

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);
      final reporte = await container.read(
        reportesProvider(
          ReportesParametros(rango: RangoReporte.dia, fechaReferencia: DateTime(2026, 3, 10)),
        ).future,
      );

      expect(reporte.masVendidos.map((r) => '${r.nombre}=${r.cantidad}'), [
        'Pollo frito · Pechuga y ala=5',
        'Pollo frito · Cadera y muslo=2',
        'Pollo frito=1',
      ]);
      // Y el detalle del día describe la línea igual que el carrito.
      final descripciones = reporte.ventasPorTurno.values
          .expand((ventas) => ventas)
          .expand((v) => v.lineas)
          .map((l) => l.descripcion)
          .toSet();
      expect(descripciones, containsAll(['Pollo frito · Pechuga y ala', 'Pollo frito']));
    });
  });

  group('el catálogo de la 1.0.0', () {
    test('se importa tal cual en el esquema nuevo, y las variantes sobreviven a exportar', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(db.close);
      await AppDatabase.crearEsquema(db);
      final servicio = TiketdataService(db);

      // Un catálogo con el formato de la 1.0.0, anterior a la columna: sus
      // filas no la traen y tienen que entrar igual.
      await servicio.importarCatalogo(
        rutaOrigen: 'test/fixtures/catalogo-1.0.0.tiketdata',
        modo: ModoImportacion.fusionar,
      );
      final productos = (await db.query('producto')).map(Producto.fromMap).toList();
      expect(productos, hasLength(6));
      expect(productos.every((p) => !p.tieneVariantes), isTrue);

      // Se le ponen variantes a uno y se exporta: el archivo nuevo las lleva.
      final pollo = productos.firstWhere((p) => p.nombre.startsWith('Pollo frito (cadera'));
      await db.update(
        'producto',
        {
          'variantes': variantesAColumna(const [
            Variante(id: 'a', nombre: 'Cadera y muslo', precio: 2300),
            Variante(id: 'b', nombre: 'Pechuga y ala', precio: 2500),
          ]),
        },
        where: 'id = ?',
        whereArgs: [pollo.id],
      );
      final temporal = Directory.systemTemp.createTempSync('vulp-tiketdata');
      addTearDown(() => temporal.deleteSync(recursive: true));
      final ruta = p.join(temporal.path, 'con-variantes.tiketdata');
      await servicio.exportarCatalogo(ruta);
      await db.delete('producto');

      await servicio.importarCatalogo(rutaOrigen: ruta, modo: ModoImportacion.fusionar);
      final recuperado = Producto.fromMap(
        (await db.query('producto', where: 'id = ?', whereArgs: [pollo.id])).single,
      );
      expect(recuperado.variantes.map((v) => v.nombre), ['Cadera y muslo', 'Pechuga y ala']);
    });
  });
}
