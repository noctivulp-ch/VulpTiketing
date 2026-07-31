import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Una app recién instalada, sin ninguna venta todavía, tiene que poder
/// consultar ventas.
///
/// El libro nacía con la primera venta, así que hasta entonces no había nada
/// adjunto y Reportes moría con `no such table: linea_venta`. Lo vio el usuario
/// en el teléfono; yo me lo había cruzado dos veces montando el banco y lo
/// atribuí al banco en vez de a la app. Es el primer día de uso de cualquier
/// negocio, no un caso borde.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('vulp-nueva'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<Database> baseNueva() async {
    final db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        singleInstance: false,
        onCreate: (db, _) => AppDatabase.crearEsquema(db),
      ),
    );
    await LibroVentasService(directorio: dir.path).adjuntarAbierto(db);
    return db;
  }

  test('sin ninguna venta, consultar ventas funciona igual', () async {
    final db = await baseNueva();
    addTearDown(db.close);

    final filas = await db.rawQuery('''
      SELECT SUM(lv.precio_aplicado * lv.cantidad) AS total
      FROM linea_venta lv
      JOIN venta v ON v.id = lv.venta_id
      WHERE v.estado = 'activa'
    ''');

    expect(filas.first['total'], isNull, reason: 'sin ventas el total es nulo, pero no revienta');
  });

  test('el libro creado al vuelo queda registrado y abierto', () async {
    final db = await baseNueva();
    addTearDown(db.close);

    final libros = LibroVentasService(directorio: dir.path);
    final abierto = await libros.libroAbierto(db);

    expect(abierto, isNotNull);
    expect(await libros.estaAdjunto(db), isTrue);
    expect(File(libros.rutaDe(abierto!.archivo)).existsSync(), isTrue);
  });

  test('abrir dos veces no crea un segundo libro', () async {
    // `adjuntarAbierto` corre en cada apertura de la app. Si creara uno nuevo
    // cada vez, el índice de libros se llenaría de archivos vacíos y el
    // archivado rodante (0025) perdería el sentido.
    final db = await baseNueva();
    addTearDown(db.close);

    final libros = LibroVentasService(directorio: dir.path);
    await libros.adjuntarAbierto(db);
    await libros.adjuntarAbierto(db);

    expect((await libros.todos(db)).length, 1);
  });
}
