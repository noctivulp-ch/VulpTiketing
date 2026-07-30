import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Regresión: `DatabaseException(database libro is already in use)`.
///
/// Bug real, encontrado en el teléfono: entrar a la app dejaba TODAS las
/// pantallas que consultan ventas mostrando ese error. No era un fallo
/// cosmético — la app quedaba inservible.
///
/// Dos defectos que se combinaban:
///
/// 1. `AppDatabase.open()` tenía un `await` entre comprobar `_instance` y
///    asignarlo, así que dos llamadas simultáneas pasaban las dos el chequeo de
///    null. Y sqflite abre en modo `singleInstance` por defecto: las dos
///    recibían LA MISMA conexión y las dos le adjuntaban el libro.
/// 2. `_adjuntar` no era idempotente, así que el segundo ATTACH reventaba.
///
/// Es fácil de disparar en uso real: al entrar, el Dashboard monta las cinco
/// pantallas de una y ocho providers piden la base en el mismo frame.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vulp-apertura');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Base principal con un libro ya registrado y su archivo en disco, que es el
  /// estado de cualquier instalación que ya vendió algo.
  Future<Database> conLibro() async {
    final db = await databaseFactory.openDatabase(
      p.join(dir.path, 'principal.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);

    final libro = await databaseFactory.openDatabase(
      p.join(dir.path, 'ventas-2026-07-30.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await aplicarEsquemaLibro(libro);
    await libro.close();

    await db.insert('libro_ventas', {
      'id': 'l1',
      'archivo': 'ventas-2026-07-30.db',
      'fecha_inicio': DateTime(2026, 7, 30).toIso8601String(),
      'fecha_fin': null,
      'dias_con_ventas': 1,
      'ultimo_dia': DateTime(2026, 7, 30).toIso8601String(),
      'cerrado': 0,
    });
    return db;
  }

  test('adjuntar dos veces la misma conexion no revienta', () async {
    final db = await conLibro();
    addTearDown(db.close);
    final servicio = LibroVentasService(directorio: dir.path);

    await servicio.adjuntarAbierto(db);
    // Este segundo ATTACH era el que mataba la app.
    await servicio.adjuntarAbierto(db);

    expect(await servicio.estaAdjunto(db), isTrue);
    expect((await db.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'], equals(0),
        reason: 'el libro tiene que quedar consultable, no a medio adjuntar');
  });

  test('adjuntar en paralelo desde varios lectores no revienta', () async {
    // Reproduce el frame de arranque del Dashboard: varios providers pidiendo
    // la base a la vez.
    final db = await conLibro();
    addTearDown(db.close);
    final servicio = LibroVentasService(directorio: dir.path);

    await Future.wait([
      for (var i = 0; i < 8; i++) servicio.adjuntarAbierto(db),
    ]);

    expect(await servicio.estaAdjunto(db), isTrue);
    expect((await db.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'], equals(0));
  });

  test('estaAdjunto distingue una base sin libro de una con libro vacio', () async {
    final db = await conLibro();
    addTearDown(db.close);
    final servicio = LibroVentasService(directorio: dir.path);

    expect(await servicio.estaAdjunto(db), isFalse);
    await servicio.adjuntarAbierto(db);
    expect(await servicio.estaAdjunto(db), isTrue);
    await servicio.desadjuntar(db);
    expect(await servicio.estaAdjunto(db), isFalse);
  });
}
