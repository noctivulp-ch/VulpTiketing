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
      version: 1,
      onCreate: (db, version) async {
        await db.execute(_createCategoria);
        await db.execute(_createProducto);
        await db.execute(_createVenta);
        await db.execute(_createLineaVenta);
      },
    );
    return _instance!;
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
