import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Esquema completo en docs/arquitectura/esquema-db.md — cualquier cambio de
/// columna se hace ahi primero, no directo aqui.
class AppDatabase {
  AppDatabase._();

  static Database? _instance;

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
    await _instance?.close();
    _instance = null;
  }

  static Future<Database> open() async {
    if (_instance != null) return _instance!;

    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _instance = await openDatabase(
      await ruta(),
      version: version,
      onCreate: (db, version) => crearEsquema(db),
      onUpgrade: (db, viejo, nuevo) async {
        // v1 -> v2: solo agrega indices. No toca columnas ni datos, asi que es
        // segura de aplicar sobre una base existente y no necesita migrar
        // filas.
        if (viejo < 2) await crearIndices(db);
      },
    );
    return _instance!;
  }

  static const version = 2;

  /// El esquema como lista ordenada de sentencias, publico a proposito: las
  /// pruebas lo aplican en bases en memoria en vez de duplicar el DDL a mano.
  /// Duplicarlo hacia que el esquema de las pruebas pudiera divergir del real
  /// en silencio — y una prueba contra un esquema que ya no existe no prueba
  /// nada.
  static const esquema = [
    _createCategoria,
    _createProducto,
    _createVenta,
    _createLineaVenta,
  ];

  /// Indices (v2). El esquema v1 no tenia ninguno, solo claves primarias, y eso
  /// se midio: con un año de volumen real el reporte del dia tardaba 5,9 s y el
  /// anual no terminaba. Reescribir las consultas para agregar en SQL bajo el
  /// dia a 280 ms; estos indices atacan lo que quedaba.
  ///
  /// Cada uno corresponde a una consulta concreta que existe hoy, no a una
  /// suposicion sobre el futuro:
  static const indices = [
    // El JOIN de reportes (`ON v.id = lv.venta_id`). Sin esto cada venta del
    // rango recorre linea_venta completa — es el de mayor impacto.
    'CREATE INDEX IF NOT EXISTS idx_linea_venta_venta ON linea_venta(venta_id);',

    // El filtro de rango de reportes
    // (`estado = 'activa' AND fecha_hora >= ? AND fecha_hora < ?`).
    'CREATE INDEX IF NOT EXISTS idx_venta_estado_fecha ON venta(estado, fecha_hora);',

    // El orden del historial (`VentaDao.listar`, ORDER BY fecha_hora DESC), que
    // no lleva WHERE y por eso no puede usar el indice compuesto de arriba.
    'CREATE INDEX IF NOT EXISTS idx_venta_fecha ON venta(fecha_hora);',

    // El GROUP BY del ranking de productos.
    'CREATE INDEX IF NOT EXISTS idx_linea_venta_producto ON linea_venta(producto_id);',
  ];

  /// Crea tablas e indices. Las pruebas usan esto para tener el esquema REAL,
  /// indices incluidos: medir sobre un esquema sin indices cuando produccion si
  /// los tiene daria numeros que no le sirven a nadie.
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

  // Sin deleted_at a proposito: una Venta nunca se borra, solo cambia de
  // estado (decision 0009). Sin campo de total: se calcula sumando
  // linea_venta, nunca se duplica aqui (ver esquema-db.md).
  static const _createVenta = '''
    CREATE TABLE venta (
      id                TEXT PRIMARY KEY,
      fecha_hora        TEXT NOT NULL,
      detalle           TEXT,
      estado            TEXT NOT NULL DEFAULT 'activa'
                         CHECK (estado IN ('activa', 'revertida')),
      motivo_reversion  TEXT,
      updated_at        TEXT NOT NULL
    );
  ''';

  // producto_id nullable + nombre_libre: linea libre sin catalogo
  // (decision 0016). Sin deleted_at: inmutable, vive y muere con su Venta.
  static const _createLineaVenta = '''
    CREATE TABLE linea_venta (
      id               TEXT PRIMARY KEY,
      venta_id         TEXT NOT NULL REFERENCES venta(id),
      producto_id      TEXT REFERENCES producto(id),
      nombre_libre     TEXT,
      precio_aplicado  REAL NOT NULL,
      cantidad         INTEGER NOT NULL DEFAULT 1,
      nota             TEXT,
      updated_at       TEXT NOT NULL,
      CHECK (
        (producto_id IS NOT NULL AND nombre_libre IS NULL) OR
        (producto_id IS NULL AND nombre_libre IS NOT NULL)
      )
    );
  ''';
}
