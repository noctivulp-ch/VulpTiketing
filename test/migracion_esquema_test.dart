import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';

/// La migración v1 → v2 (índices) tiene que aplicarse sobre bases QUE YA
/// EXISTEN, no solo en instalaciones nuevas: la tablet del negocio ya tiene
/// datos. Una migración que solo corre en `onCreate` dejaría al usuario real
/// sin índices para siempre, y en silencio — que es el peor tipo de fallo.
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

  Future<List<String>> indicesDe(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%' ORDER BY name",
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  test('una base v1 con datos se migra a v2 sin perder nada', () async {
    final ruta = p.join(temporal.path, 'v1.db');

    // Base v1: tablas SIN indices, tal como quedaron las instalaciones que ya
    // existen. Se crea a mano con las sentencias de tabla, sin `crearIndices`.
    final v1 = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onCreate: (db, _) async {
          for (final sentencia in AppDatabase.esquema) {
            await db.execute(sentencia);
          }
        },
      ),
    );

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
    expect(await indicesDe(v1), isEmpty, reason: 'v1 no debe tener indices');
    await v1.close();

    // Ahora se abre con la version y las migraciones REALES de la app.
    final v2 = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        singleInstance: false,
        onCreate: (db, _) => AppDatabase.crearEsquema(db),
        onUpgrade: (db, viejo, nuevo) async {
          if (viejo < 2) await AppDatabase.crearIndices(db);
        },
      ),
    );
    addTearDown(v2.close);

    expect(await v2.getVersion(), equals(AppDatabase.version));

    // Los indices tienen que estar…
    final indices = await indicesDe(v2);
    expect(indices, hasLength(AppDatabase.indices.length),
        reason: 'faltan indices tras migrar: $indices');

    // …y los datos tienen que seguir intactos. Esta migracion no toca columnas
    // ni filas, asi que perder algo seria un error grave.
    final ventas = await v2.query('venta');
    final lineas = await v2.query('linea_venta');
    expect(ventas, hasLength(1));
    expect(lineas, hasLength(1));
    expect(lineas.first['precio_aplicado'], equals(1500));
    expect(lineas.first['cantidad'], equals(2));
  });

  test('migrar dos veces no falla', () async {
    // `onUpgrade` no deberia volver a correr, pero los indices usan
    // IF NOT EXISTS igual: una migracion que revienta al reintentarse deja la
    // app sin poder abrir la base nunca mas.
    final ruta = p.join(temporal.path, 'idempotente.db');

    Future<Database> abrir() => databaseFactory.openDatabase(
          ruta,
          options: OpenDatabaseOptions(
            version: AppDatabase.version,
            singleInstance: false,
            onCreate: (db, _) => AppDatabase.crearEsquema(db),
            onUpgrade: (db, viejo, nuevo) async {
              if (viejo < 2) await AppDatabase.crearIndices(db);
            },
          ),
        );

    final primera = await abrir();
    await AppDatabase.crearIndices(primera); // simula un reintento
    expect(await indicesDe(primera), hasLength(AppDatabase.indices.length));
    await primera.close();

    final segunda = await abrir();
    addTearDown(segunda.close);
    expect(await indicesDe(segunda), hasLength(AppDatabase.indices.length));
  });

  test('los indices que declara el esquema son los que dice usar', () async {
    // Guarda contra agregar un indice y olvidar el comentario que lo justifica,
    // o al reves: dejar un comentario de un indice que ya no existe.
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await AppDatabase.crearEsquema(db);

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
}
