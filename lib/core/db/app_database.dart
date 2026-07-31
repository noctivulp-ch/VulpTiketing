import 'dart:io';

import 'package:path/path.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../features/venta/libro_ventas.dart';

/// Esquema completo en docs/arquitectura/esquema-db.md — cualquier cambio de
/// columna se hace ahi primero, no directo aqui.
class AppDatabase {
  AppDatabase._();

  static Database? _instance;

  /// La apertura en curso, para que N lectores concurrentes compartan UNA.
  ///
  /// `open()` tenía un `await` entre comprobar `_instance` y asignarlo, así que
  /// dos llamadas simultáneas pasaban las dos el chequeo de null. Y como
  /// sqflite abre en modo `singleInstance` por defecto, las dos recibían LA
  /// MISMA conexión y las dos le adjuntaban el libro: la segunda moría con
  /// `database libro is already in use` y dejaba la app sin poder consultar
  /// ventas en ninguna pantalla.
  ///
  /// Es fácil de disparar: al entrar, el Dashboard monta las cinco pantallas de
  /// una y ocho providers distintos piden la base en el mismo frame.
  static Future<Database>? _aperturaEnCurso;

  /// Ruta del archivo fisico — usada por TiketbackService para
  /// leer/reemplazar el archivo directo en exportar/restaurar (0006).
  static Future<String> ruta() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, 'vulp_tiketing.db');
  }

  /// Cierra la conexion activa, si hay una. Necesario antes de reemplazar
  /// el archivo fisico al restaurar un .tiketback — sqflite no permite
  /// sobreescribir un archivo con una conexion abierta de forma segura.
  static Future<void> close() async {
    _aperturaEnCurso = null;
    final db = _instance;
    _instance = null;
    if (db == null) return;
    // Soltar el libro ANTES de cerrar: si la conexión sobreviviera al cierre
    // —sqflite la comparte entre aperturas del mismo archivo— volvería con el
    // alias todavía tomado y el siguiente ATTACH fallaría.
    await LibroVentasService(directorio: p.dirname(await ruta())).desadjuntar(db);
    await db.close();
  }

  /// Deja `databaseFactory` utilizable en esta plataforma.
  ///
  /// Es publico y separado de [open] porque hay codigo que abre bases SIN pasar
  /// por la conexion principal: `TiketbackService` abre el archivo restaurado y
  /// un temporal, y `LibroVentasService` abre cada libro para crearle su
  /// esquema. Cuando esto vivia solo dentro de [open], restaurar un backup en
  /// una app recien abierta —antes de que nadie hubiera tocado la base— moria
  /// con `databaseFactory not initialized`.
  ///
  /// Idempotente: llamarlo de mas no cuesta nada.
  static void inicializarFactory() {
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  /// Comparte una sola apertura entre todos los que la pidan a la vez.
  static Future<Database> open() async {
    final abierta = _instance;
    if (abierta != null) return abierta;

    final enCurso = _aperturaEnCurso ??= _abrir();
    try {
      return await enCurso;
    } finally {
      // Se limpia pase lo que pase: si la apertura falló, el siguiente intento
      // tiene que poder reintentar en vez de quedarse pegado a un futuro roto.
      if (identical(_aperturaEnCurso, enCurso)) _aperturaEnCurso = null;
    }
  }

  static Future<Database> _abrir() async {
    inicializarFactory();

    final db = await openDatabase(
      await ruta(),
      version: version,
      onCreate: (db, version) => crearEsquema(db),
      onUpgrade: (db, viejo, nuevo) async {
        // v1 -> v2: solo agrega indices. No toca columnas ni datos, asi que es
        // segura de aplicar sobre una base existente y no necesita migrar
        // filas.
        if (viejo < 2) await crearIndicesLegacyV2(db);

        // v2 -> v3: las ventas se mudan de la base principal a su primer libro
        // (decision 0025). Es la UNICA vez que se mueven datos: de aca en
        // adelante las ventas nacen ya en su libro.
        if (viejo < 3) {
          await migrarVentasALibro(db, p.dirname(await ruta()));
        }
      },
    );

    // El libro abierto se adjunta aca: desde este momento `SELECT * FROM venta`
    // resuelve contra el, sin que el resto del codigo tenga que calificar nada.
    await LibroVentasService(directorio: p.dirname(await ruta())).adjuntarAbierto(db);

    // `_instance` se asigna al FINAL, con la base ya usable. Asignarla antes
    // dejaba una ventana donde otro lector se la llevaba a medio preparar, sin
    // el libro adjunto.
    _instance = db;
    return db;
  }

  static const version = 3;

  /// El esquema como lista ordenada de sentencias, publico a proposito: las
  /// pruebas lo aplican en bases en memoria en vez de duplicar el DDL a mano.
  /// Duplicarlo hacia que el esquema de las pruebas pudiera divergir del real
  /// en silencio — y una prueba contra un esquema que ya no existe no prueba
  /// nada.
  ///
  /// `venta` y `linea_venta` NO estan aca desde v3: viven en los libros
  /// (decision 0025). Que no existan en la base principal no es un descuido, es
  /// lo que hace que funcione — SQLite resuelve los nombres sin calificar
  /// contra las bases adjuntas, asi que `SELECT * FROM venta` va solo al libro
  /// abierto y el resto del codigo no tuvo que cambiar.
  static const esquema = [_createCategoria, _createProducto, _createLibroVentas];

  /// Indices de la base principal. Desde v3 los de `venta`/`linea_venta` no
  /// estan aca: se aplican a cada libro (ver `esquemaLibro`), porque es ahi
  /// donde viven esas tablas.
  static const indices = [
    // Agrupar productos por categoria, que es uno de los ordenes de la
    // Ventana 1 (decision 0018).
    'CREATE INDEX IF NOT EXISTS idx_producto_categoria ON producto(categoria_id);',
  ];

  /// Indices que tenia la base principal en v2, cuando `venta` y `linea_venta`
  /// todavia vivian ahi. Se conservan SOLO para el camino de actualizacion
  /// v1 -> v2: una base v1 pasa por ese estado intermedio antes de que la
  /// migracion v3 mude las ventas a su libro.
  ///
  /// Un esquema nuevo no los usa nunca — sus equivalentes estan en
  /// `esquemaLibro`.
  static const indicesLegacyV2 = [
    'CREATE INDEX IF NOT EXISTS idx_linea_venta_venta ON linea_venta(venta_id);',
    'CREATE INDEX IF NOT EXISTS idx_venta_estado_fecha ON venta(estado, fecha_hora);',
    'CREATE INDEX IF NOT EXISTS idx_venta_fecha ON venta(fecha_hora);',
    'CREATE INDEX IF NOT EXISTS idx_linea_venta_producto ON linea_venta(producto_id);',
  ];

  /// Crea la base principal completa: catalogo, indice de libros e indices.
  ///
  /// OJO: esto NO crea `venta` ni `linea_venta` — esas viven en los libros. Una
  /// prueba que necesite ventas tiene que aplicar ademas `esquemaLibro`
  /// (`aplicarEsquemaLibro`), igual que hace la app al abrir un libro.
  static Future<void> crearEsquema(DatabaseExecutor db) async {
    for (final sentencia in esquema) {
      await db.execute(sentencia);
    }
    await crearIndices(db);
  }

  static Future<void> crearIndices(DatabaseExecutor db) async {
    for (final sentencia in indices) {
      await db.execute(sentencia);
    }
  }

  static Future<void> crearIndicesLegacyV2(DatabaseExecutor db) async {
    for (final sentencia in indicesLegacyV2) {
      await db.execute(sentencia);
    }
  }

  /// Migracion v2 -> v3: mueve `venta` y `linea_venta` de la base principal al
  /// primer libro, crea el indice y las quita de la principal.
  ///
  /// Se escribio como una mudanza real y no como un `DROP` aunque el proyecto
  /// todavia no esta en uso comercial: una migracion que descarta ventas queda
  /// en el codigo para siempre y podria correr en la maquina de alguien. El
  /// costo de hacerla bien era bajo.
  ///
  /// Es la unica vez en la vida del proyecto que las ventas se mueven de
  /// archivo: de aca en adelante nacen ya en su libro (decision 0025).
  static Future<void> migrarVentasALibro(Database db, String directorio) async {
    await db.execute(_createLibroVentas);

    final ventas = await db.query('venta', orderBy: 'fecha_hora');
    if (ventas.isEmpty) {
      // Sin ventas no hace falta libro: el primero se crea con la primera
      // venta real, asi una instalacion nueva no arranca con archivos sueltos.
      await db.execute('DROP TABLE IF EXISTS linea_venta');
      await db.execute('DROP TABLE IF EXISTS venta');
      return;
    }

    final lineas = await db.query('linea_venta');
    final primera = DateTime.parse(ventas.first['fecha_hora'] as String);
    final ultima = DateTime.parse(ventas.last['fecha_hora'] as String);

    final servicio = LibroVentasService(directorio: directorio);
    final archivo = 'ventas-${primera.toIso8601String().split("T").first}.db';
    final libro = await databaseFactory.openDatabase(
      servicio.rutaDe(archivo),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    for (final sentencia in esquemaLibro) {
      await libro.execute(sentencia);
    }
    await libro.transaction((txn) async {
      for (final fila in ventas) {
        await txn.insert('venta', fila);
      }
      for (final fila in lineas) {
        await txn.insert('linea_venta', fila);
      }
    });

    // Verificacion antes de soltar el original: si la copia no cuadra, no se
    // borra nada y la migracion falla ruidosamente.
    final copiadas = (await libro.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'] as int;
    final copiadasLineas =
        (await libro.rawQuery('SELECT COUNT(*) c FROM linea_venta')).first['c'] as int;
    await libro.close();
    if (copiadas != ventas.length || copiadasLineas != lineas.length) {
      throw StateError(
        'migracion v3: el libro quedo con $copiadas/${ventas.length} ventas y '
        '$copiadasLineas/${lineas.length} lineas — no se borra nada',
      );
    }

    // Dias distintos con ventas, que es la unidad con la que se mide un libro.
    final dias = ventas.map((v) => (v['fecha_hora'] as String).split('T').first).toSet().length;

    await db.insert('libro_ventas', {
      'id': const Uuid().v4(),
      'archivo': archivo,
      'fecha_inicio': DateTime(primera.year, primera.month, primera.day).toIso8601String(),
      'fecha_fin': null,
      'dias_con_ventas': dias,
      'ultimo_dia': DateTime(ultima.year, ultima.month, ultima.day).toIso8601String(),
      'cerrado': 0,
    });

    await db.execute('DROP TABLE linea_venta');
    await db.execute('DROP TABLE venta');
  }

  static const _createCategoria = '''
    CREATE TABLE categoria (
      id            TEXT PRIMARY KEY,
      nombre        TEXT NOT NULL,
      updated_at    TEXT NOT NULL,
      deleted_at    TEXT
    );
  ''';

  static const _createProducto = '''
    CREATE TABLE producto (
      id            TEXT PRIMARY KEY,
      nombre        TEXT NOT NULL,
      imagen        TEXT,
      categoria_id  TEXT REFERENCES categoria(id),
      precio_base   REAL NOT NULL,
      updated_at    TEXT NOT NULL,
      deleted_at    TEXT
    );
  ''';

  /// Indice de libros de ventas (decision 0025). El nombre del archivo
  /// (`inicio_final.db`) es para que una persona entienda la carpeta de un
  /// vistazo; ESTA TABLA es la fuente de verdad de la app. Depender de parsear
  /// nombres de archivo la dejaria sin saber que tiene ante un renombrado
  /// interrumpido o un archivo movido a mano.
  static const _createLibroVentas = '''
    CREATE TABLE libro_ventas (
      id               TEXT PRIMARY KEY,
      archivo          TEXT NOT NULL,
      fecha_inicio     TEXT NOT NULL,
      fecha_fin        TEXT,
      dias_con_ventas  INTEGER NOT NULL DEFAULT 0,
      ultimo_dia       TEXT,
      cerrado          INTEGER NOT NULL DEFAULT 0
    );
  ''';
}
