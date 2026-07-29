import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/features/sync/device_discovery_service.dart';
import 'package:vulp_tiketing/features/sync/sync_client.dart';
import 'package:vulp_tiketing/features/sync/sync_server.dart';

Future<Database> _abrirDbConEsquema() async {
  // singleInstance: false es obligatorio aquí — dos bases ":memory:" abiertas
  // con el mismo path por defecto comparten la misma instancia cacheada por
  // sqflite, lo cual arruinaría el propósito del test (servidor y cliente
  // deben ser bases físicamente independientes).
  final db = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
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
  await db.execute('''
    CREATE TABLE venta (
      id TEXT PRIMARY KEY, fecha_hora TEXT NOT NULL, detalle TEXT,
      estado TEXT NOT NULL DEFAULT 'activa', motivo_reversion TEXT, updated_at TEXT NOT NULL
    );
  ''');
  await db.execute('''
    CREATE TABLE linea_venta (
      id TEXT PRIMARY KEY, venta_id TEXT NOT NULL, producto_id TEXT, nombre_libre TEXT,
      precio_aplicado REAL NOT NULL, cantidad INTEGER NOT NULL DEFAULT 1, nota TEXT,
      updated_at TEXT NOT NULL
    );
  ''');
  return db;
}

Map<String, Object?> _producto({
  required String id,
  required String nombre,
  String updatedAt = '2026-01-01T00:00:00.000',
  String? deletedAt,
}) => {
      'id': id,
      'nombre': nombre,
      'imagen': null,
      'categoria_id': null,
      'precio_base': 800,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };

void main() {
  late Database dbServidor;
  late Database dbCliente;
  late SyncServer servidor;
  late PeerVisible peer;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dbServidor = await _abrirDbConEsquema();
    dbCliente = await _abrirDbConEsquema();
    servidor = SyncServer(dbServidor);
    final puerto = await servidor.iniciar();
    peer = PeerVisible(deviceId: 'servidor', rol: 'gerente', direccion: '127.0.0.1', puerto: puerto);
  });

  tearDown(() async {
    await servidor.detener();
    await dbServidor.close();
    await dbCliente.close();
  });

  test('sincronizarCon trae filas nuevas del peer via HTTP real', () async {
    await dbServidor.insert('producto', _producto(id: 'p1', nombre: 'Café'));
    await dbServidor.insert('venta', {
      'id': 'v1',
      'fecha_hora': '2026-01-01T00:00:00.000',
      'detalle': null,
      'estado': 'activa',
      'motivo_reversion': null,
      'updated_at': '2026-01-01T00:00:00.000',
    });
    await dbServidor.insert('linea_venta', {
      'id': 'l1',
      'venta_id': 'v1',
      'producto_id': 'p1',
      'nombre_libre': null,
      'precio_aplicado': 800,
      'cantidad': 2,
      'nota': null,
      'updated_at': '2026-01-01T00:00:00.000',
    });

    await SyncClient(dbCliente).sincronizarCon(peer);

    final productos = await dbCliente.query('producto');
    final ventas = await dbCliente.query('venta');
    final lineas = await dbCliente.query('linea_venta');
    expect(productos, hasLength(1));
    expect(productos.first['nombre'], 'Café');
    expect(ventas, hasLength(1));
    expect(lineas, hasLength(1));
  });

  test('sincronizarCon propaga tombstones (deleted_at) del peer', () async {
    await dbCliente.insert('producto', _producto(id: 'p1', nombre: 'Café'));
    await dbServidor.insert(
      'producto',
      _producto(id: 'p1', nombre: 'Café', updatedAt: '2026-02-01T00:00:00.000', deletedAt: '2026-02-01T00:00:00.000'),
    );

    await SyncClient(dbCliente).sincronizarCon(peer);

    final p1 = (await dbCliente.query('producto', where: 'id = ?', whereArgs: ['p1'])).first;
    expect(p1['deleted_at'], isNotNull);
  });

  test('sincronizarCon respeta LWW: un cambio local mas reciente no se pierde', () async {
    await dbServidor.insert('producto', _producto(id: 'p1', nombre: 'Café', updatedAt: '2026-01-01T00:00:00.000'));
    await dbCliente.insert(
      'producto',
      _producto(id: 'p1', nombre: 'Café especial', updatedAt: '2026-06-01T00:00:00.000'),
    );

    await SyncClient(dbCliente).sincronizarCon(peer);

    final p1 = (await dbCliente.query('producto', where: 'id = ?', whereArgs: ['p1'])).first;
    expect(p1['nombre'], 'Café especial', reason: 'el cambio local es mas reciente que el del servidor');
  });
}
