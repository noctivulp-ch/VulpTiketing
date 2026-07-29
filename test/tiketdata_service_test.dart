import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/features/import_export/tiketdata_service.dart';

Map<String, Object?> _producto({
  required String id,
  required String nombre,
  double precioBase = 800,
  String updatedAt = '2026-01-01T00:00:00.000',
}) => {
      'id': id,
      'nombre': nombre,
      'imagen': null,
      'categoria_id': null,
      'precio_base': precioBase,
      'updated_at': updatedAt,
      'deleted_at': null,
    };

void main() {
  late Database db;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tiketdata_test_');
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE categoria (
        id TEXT PRIMARY KEY, nombre TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE producto (
        id TEXT PRIMARY KEY, nombre TEXT NOT NULL, imagen TEXT, categoria_id TEXT,
        precio_base REAL NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
      );
    ''');
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('exportar + importar (fusionar) recupera el producto en un catálogo vacío', () async {
    final servicio = TiketdataService(db);
    await db.insert('producto', _producto(id: 'p1', nombre: 'Café'));

    final ruta = '${tempDir.path}/catalogo.tiketdata';
    await servicio.exportarCatalogo(ruta);
    await db.delete('producto'); // simula otro dispositivo con catálogo vacío

    await servicio.importarCatalogo(rutaOrigen: ruta, modo: ModoImportacion.fusionar);

    final filas = await db.query('producto');
    expect(filas, hasLength(1));
    expect(filas.first['nombre'], 'Café');
  });

  test('reemplazar descontinúa lo que no está en el archivo, fusionar no lo toca', () async {
    final servicio = TiketdataService(db);
    await db.insert('producto', _producto(id: 'p1', nombre: 'Café'));
    final ruta = '${tempDir.path}/catalogo.tiketdata';
    await servicio.exportarCatalogo(ruta); // el archivo solo tiene p1

    await db.insert('producto', _producto(id: 'p2', nombre: 'Jugo')); // extra local, no en el archivo

    // Fusionar: p2 no se toca.
    await servicio.importarCatalogo(rutaOrigen: ruta, modo: ModoImportacion.fusionar);
    var p2 = (await db.query('producto', where: 'id = ?', whereArgs: ['p2'])).first;
    expect(p2['deleted_at'], isNull);

    // Reemplazar: p2 se descontinúa (soft-delete, no se borra la fila).
    await servicio.importarCatalogo(rutaOrigen: ruta, modo: ModoImportacion.reemplazar);
    p2 = (await db.query('producto', where: 'id = ?', whereArgs: ['p2'])).first;
    expect(p2['deleted_at'], isNotNull);

    final p1 = (await db.query('producto', where: 'id = ?', whereArgs: ['p1'])).first;
    expect(p1['deleted_at'], isNull, reason: 'p1 sí está en el archivo, no debe descontinuarse');
  });

  test('LWW: un cambio local más reciente no se pierde al importar', () async {
    final servicio = TiketdataService(db);
    await db.insert(
      'producto',
      _producto(id: 'p1', nombre: 'Café', precioBase: 800, updatedAt: '2026-01-01T00:00:00.000'),
    );
    final ruta = '${tempDir.path}/catalogo.tiketdata';
    await servicio.exportarCatalogo(ruta); // archivo con precio 800, de enero

    await db.update(
      'producto',
      {'nombre': 'Café especial', 'precio_base': 1000.0, 'updated_at': '2026-06-01T00:00:00.000'},
      where: 'id = ?',
      whereArgs: ['p1'],
    );

    await servicio.importarCatalogo(rutaOrigen: ruta, modo: ModoImportacion.fusionar);

    final p1 = (await db.query('producto', where: 'id = ?', whereArgs: ['p1'])).first;
    expect(p1['nombre'], 'Café especial');
    expect(p1['precio_base'], 1000.0);
  });
}
