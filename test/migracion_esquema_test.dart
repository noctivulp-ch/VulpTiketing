import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Las migraciones tienen que aplicarse sobre bases QUE YA EXISTEN, no solo en
/// instalaciones nuevas. Una migración que solo corriera en `onCreate` dejaría
/// al usuario real con el esquema viejo para siempre, y en silencio — que es el
/// peor tipo de fallo.
///
/// Hay dos saltos:
/// - **v1 → v2**: agrega índices. No toca datos.
/// - **v2 → v3**: muda `venta` y `linea_venta` a su primer libro
///   ([decisión 0025](../docs/decisiones/0025-archivado-anual-rodante.md)). Es
///   la única vez en la vida del proyecto que las ventas cambian de archivo.
/// - **v3 → v4**: la categoría gana la columna `icono`, para poder elegirlo a
///   mano cuando el acierto por nombre falla.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temporal;

  setUp(() {
    temporal = Directory.systemTemp.createTempSync('vulp-migracion');
  });

  tearDown(() {
    if (temporal.existsSync()) temporal.deleteSync(recursive: true);
  });

  Future<List<String>> indicesDe(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%' ORDER BY name",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Crea una base tal como era en v1: catálogo y ventas juntas, sin índices.
  Future<Database> crearV1(String ruta) async {
    return databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) async {
          await db.execute(AppDatabase.esquema[0]); // categoria
          await db.execute(AppDatabase.esquema[1]); // producto
          // En v1 las ventas vivían acá. El DDL es el mismo que hoy usa un
          // libro, así que se reutiliza en vez de duplicarlo.
          await aplicarEsquemaLibroSinIndices(db);
        },
      ),
    );
  }

  /// Abre con la versión y las migraciones REALES de la app.
  Future<Database> abrirConMigracionesReales(String ruta, String directorio) {
    return databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        singleInstance: false,
        onCreate: (db, _) => AppDatabase.crearEsquema(db),
        onUpgrade: (db, viejo, nuevo) async {
          if (viejo < 2) await AppDatabase.crearIndicesLegacyV2(db);
          if (viejo < 3) await AppDatabase.migrarVentasALibro(db, directorio);
        },
      ),
    );
  }

  test('una base v1 con ventas llega a v3 sin perder nada', () async {
    final ruta = p.join(temporal.path, 'v1.db');
    final v1 = await crearV1(ruta);

    final fecha = DateTime(2026, 5, 1, 12).toIso8601String();
    await v1.insert('venta', {
      'id': 'v1',
      'fecha_hora': fecha,
      'estado': 'activa',
      'updated_at': fecha,
    });
    await v1.insert('linea_venta', {
      'id': 'l1',
      'venta_id': 'v1',
      'nombre_libre': 'algo',
      'precio_aplicado': 1500,
      'cantidad': 2,
      'updated_at': fecha,
    });
    expect(await indicesDe(v1), isEmpty, reason: 'v1 no tenía índices');
    await v1.close();

    final v3 = await abrirConMigracionesReales(ruta, temporal.path);
    addTearDown(v3.close);

    expect(await v3.getVersion(), equals(AppDatabase.version));

    // Las ventas ya no están en la base principal…
    final quedan = await v3.rawQuery(
      "SELECT COUNT(*) c FROM main.sqlite_master "
      "WHERE type='table' AND name IN ('venta','linea_venta')",
    );
    expect(quedan.first['c'], equals(0));

    // …sino en un libro, con el importe intacto.
    final libro = await LibroVentasService(directorio: temporal.path).libroAbierto(v3);
    expect(libro, isNotNull);
    expect(libro!.diasConVentas, equals(1));

    final libroDb = await databaseFactory.openDatabase(
      p.join(temporal.path, libro.archivo),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final lineas = await libroDb.query('linea_venta');
    await libroDb.close();

    expect(lineas, hasLength(1));
    expect(lineas.first['precio_aplicado'], equals(1500));
    expect(lineas.first['cantidad'], equals(2));

    // El catálogo, que no se muda, sigue en su lugar.
    final tablasPrincipal = await v3.rawQuery(
      "SELECT name FROM main.sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    expect(
      tablasPrincipal.map((r) => r['name']),
      containsAll(['categoria', 'libro_ventas', 'producto']),
    );
  });

  test('una base v1 SIN ventas llega a v3 sin crear libros vacios', () async {
    final ruta = p.join(temporal.path, 'vacia.db');
    final v1 = await crearV1(ruta);
    await v1.close();

    final v3 = await abrirConMigracionesReales(ruta, temporal.path);
    addTearDown(v3.close);

    expect(await LibroVentasService(directorio: temporal.path).libroAbierto(v3), isNull);
    final sueltos = temporal
        .listSync()
        .map((e) => p.basename(e.path))
        .where((n) => n.startsWith('ventas-'));
    expect(sueltos, isEmpty, reason: 'el primer libro se crea con la primera venta, no al migrar');
  });

  test('migrar dos veces no falla', () async {
    // `onUpgrade` no debería repetirse, pero una migración que revienta al
    // reintentarse deja la app sin poder abrir la base nunca más.
    final ruta = p.join(temporal.path, 'idempotente.db');

    final primera = await abrirConMigracionesReales(ruta, temporal.path);
    await AppDatabase.crearIndices(primera); // simula un reintento
    await primera.close();

    final segunda = await abrirConMigracionesReales(ruta, temporal.path);
    addTearDown(segunda.close);
    expect(await segunda.getVersion(), equals(AppDatabase.version));
  });

  test('la base principal solo declara indices de sus propias tablas', () async {
    // Desde v3 los índices de `venta`/`linea_venta` viven en el libro, porque
    // es ahí donde están esas tablas. Declararlos acá reventaría al crear el
    // esquema.
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await AppDatabase.crearEsquema(db);

    expect(await indicesDe(db), equals(['idx_producto_categoria']));
  });

  test('un libro trae sus propios indices', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await aplicarEsquemaLibro(db);

    expect(
      await indicesDe(db),
      equals([
        'idx_linea_venta_producto',
        'idx_linea_venta_venta',
        'idx_venta_estado_fecha',
        'idx_venta_fecha',
      ]),
    );
  });

  group('v3 → v4: el icono de la categoría', () {
    /// Una base tal como la dejaba v3: sin la columna `icono`.
    Future<Database> baseV3() async {
      final db = await databaseFactory.openDatabase(
        p.join(temporal.path, 'v3.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute(
        'CREATE TABLE categoria ('
        '  id TEXT PRIMARY KEY,'
        '  nombre TEXT NOT NULL,'
        '  updated_at TEXT NOT NULL,'
        '  deleted_at TEXT'
        ');',
      );
      await db.insert('categoria', {
        'id': 'cat',
        'nombre': 'Arroces',
        'updated_at': DateTime(2026).toIso8601String(),
      });
      return db;
    }

    test('agrega la columna sin tocar las filas que ya estaban', () async {
      // La columna es NULLABLE y sin DEFAULT a propósito: `NULL` significa "el
      // que salga del nombre", que es exactamente lo que hacían todas las
      // categorías hasta ahora. Así la migración no tiene que reescribir nada
      // —y no puede equivocarse al hacerlo.
      final db = await baseV3();

      await AppDatabase.agregarIconoDeCategoria(db);

      final filas = await db.query('categoria');
      expect(filas, hasLength(1));
      expect(filas.first['nombre'], 'Arroces');
      expect(filas.first['icono'], isNull, reason: 'debe quedar en automático');
      await db.close();
    });

    test('aplicarla dos veces no rompe', () async {
      // Pasa de verdad: una base a medio migrar, o un `onUpgrade` que corre tras
      // restaurar un backup. Un `ALTER TABLE` repetido es un error fatal de
      // SQLite, así que la migración comprueba antes de tocar.
      final db = await baseV3();

      await AppDatabase.agregarIconoDeCategoria(db);
      await AppDatabase.agregarIconoDeCategoria(db);

      expect(await db.query('categoria'), hasLength(1));
      await db.close();
    });

    test('una base nueva ya la trae', () async {
      // El esquema de `onCreate` y el resultado de migrar tienen que coincidir:
      // si divergen, una instalación nueva y una actualizada dejan de ser la
      // misma app.
      final db = await databaseFactory.openDatabase(
        p.join(temporal.path, 'nueva.db'),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await AppDatabase.crearEsquema(db);

      final columnas = await db.rawQuery('PRAGMA table_info(categoria)');

      expect(columnas.map((c) => c['name']), contains('icono'));
      await db.close();
    });
  });
}
