import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/sync/device_discovery_service.dart';
import 'package:vulp_tiketing/features/sync/sync_client.dart';
import 'package:vulp_tiketing/features/sync/sync_server.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Sync sobre HTTP real y sobre la topología real: base principal con el
/// catálogo, y las ventas en un libro adjunto
/// ([decisión 0025](../docs/decisiones/0025-archivado-anual-rodante.md)).
///
/// Antes esta prueba creaba las cuatro tablas juntas en una sola base en
/// memoria. Pasaba, pero no probaba nada de lo que hoy puede romperse: que el
/// servidor sobreviva a no tener libro, que las ventas remotas aterricen en el
/// libro y no en la principal, y que el índice quede describiendo lo que el
/// libro realmente tiene.
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
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dirServidor;
  late Directory dirCliente;
  late Database dbServidor;
  late Database dbCliente;
  late LibroVentasService librosServidor;
  late LibroVentasService librosCliente;
  late SyncServer servidor;
  late PeerVisible peer;

  /// Una instalación completa: su carpeta, su base principal, su servicio de
  /// libros. Sin libro todavía — igual que un dispositivo recién instalado.
  Future<(Directory, Database, LibroVentasService)> instalacion(String nombre) async {
    final dir = Directory.systemTemp.createTempSync('vulp-sync-$nombre');
    // singleInstance: false es obligatorio — dos bases abiertas con el mismo
    // path comparten la instancia cacheada de sqflite, y servidor y cliente
    // tienen que ser bases físicamente independientes.
    final db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    return (dir, db, LibroVentasService(directorio: dir.path));
  }

  setUp(() async {
    (dirServidor, dbServidor, librosServidor) = await instalacion('servidor');
    (dirCliente, dbCliente, librosCliente) = await instalacion('cliente');
    servidor = SyncServer(dbServidor);
    final puerto = await servidor.iniciar();
    peer = PeerVisible(
      deviceId: 'servidor', rol: 'gerente', direccion: '127.0.0.1', puerto: puerto,
    );
  });

  tearDown(() async {
    await servidor.detener();
    await dbServidor.close();
    await dbCliente.close();
    if (dirServidor.existsSync()) dirServidor.deleteSync(recursive: true);
    if (dirCliente.existsSync()) dirCliente.deleteSync(recursive: true);
  });

  /// Registra una venta como lo hace la caja: rota el libro y escribe.
  Future<void> vender(
    Database db,
    LibroVentasService libros,
    DateTime cuando, {
    String? id,
    double precio = 800,
  }) async {
    await libros.prepararPara(db, cuando);
    final ventaId = id ?? 'v-${cuando.toIso8601String()}';
    await db.insert('venta', {
      'id': ventaId,
      'fecha_hora': cuando.toIso8601String(),
      'estado': 'activa',
      'updated_at': cuando.toIso8601String(),
    });
    await db.insert('linea_venta', {
      'id': 'l-$ventaId',
      'venta_id': ventaId,
      'nombre_libre': 'algo',
      'precio_aplicado': precio,
      'cantidad': 1,
      'updated_at': cuando.toIso8601String(),
    });
  }

  SyncClient clienteSync() => SyncClient(dbCliente, libros: librosCliente);

  test('un peer sin ninguna venta igual sincroniza su catalogo', () async {
    // Este es el fallo que existía: sin libro abierto no hay tabla `venta`, el
    // servidor devolvía 500 y el cliente se comía la excepción en silencio.
    // Resultado: un dispositivo recién instalado tampoco recibía el MENÚ.
    await dbServidor.insert('producto', _producto(id: 'p1', nombre: 'Café'));

    await clienteSync().sincronizarCon(peer);

    final productos = await dbCliente.query('producto');
    expect(productos, hasLength(1));
    expect(productos.first['nombre'], 'Café');
  });

  test('las ventas del peer aterrizan en el libro del cliente, no en su base principal', () async {
    await dbServidor.insert('producto', _producto(id: 'p1', nombre: 'Café'));
    await vender(dbServidor, librosServidor, DateTime(2026, 3, 10, 12));

    await clienteSync().sincronizarCon(peer);

    expect(await dbCliente.query('venta'), hasLength(1));
    expect(await dbCliente.query('linea_venta'), hasLength(1));

    // La base principal del cliente NO puede tener la tabla: si la tuviera,
    // las ventas quedarían fuera de todo libro y ningún backup las llevaría.
    final enPrincipal = await dbCliente.rawQuery(
      "SELECT COUNT(*) c FROM main.sqlite_master WHERE type='table' AND name='venta'",
    );
    expect(enPrincipal.first['c'], equals(0));

    final libro = await librosCliente.libroAbierto(dbCliente);
    expect(libro, isNotNull, reason: 'recibir ventas tiene que abrir un libro');
    final archivo = await databaseFactory.openDatabase(
      librosCliente.rutaDe(libro!.archivo),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final cuantas = (await archivo.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'];
    await archivo.close();
    expect(cuantas, equals(1));
  });

  test('tras el sync el indice cuenta los dias que el libro realmente tiene', () async {
    for (var dia = 1; dia <= 3; dia++) {
      await vender(dbServidor, librosServidor, DateTime(2026, 3, dia, 12));
    }

    await clienteSync().sincronizarCon(peer);

    final libro = await librosCliente.libroAbierto(dbCliente);
    expect(libro!.diasConVentas, equals(3),
        reason: 'sin recontar, un libro que recibe todo por sync no contaría '
            'ningún día y no rotaría nunca');
  });

  test('sincronizar dos veces no altera el conteo de dias', () async {
    for (var dia = 1; dia <= 3; dia++) {
      await vender(dbServidor, librosServidor, DateTime(2026, 3, dia, 12));
    }

    await clienteSync().sincronizarCon(peer);
    await clienteSync().sincronizarCon(peer);

    final libro = await librosCliente.libroAbierto(dbCliente);
    expect(libro!.diasConVentas, equals(3),
        reason: 'el sync reenvía las mismas filas: contar tiene que ser idempotente');
    expect(await dbCliente.query('venta'), hasLength(3));
  });

  test('sincronizarCon propaga tombstones (deleted_at) del peer', () async {
    await dbCliente.insert('producto', _producto(id: 'p1', nombre: 'Café'));
    await dbServidor.insert(
      'producto',
      _producto(
        id: 'p1',
        nombre: 'Café',
        updatedAt: '2026-02-01T00:00:00.000',
        deletedAt: '2026-02-01T00:00:00.000',
      ),
    );

    await clienteSync().sincronizarCon(peer);

    final p1 = (await dbCliente.query('producto', where: 'id = ?', whereArgs: ['p1'])).first;
    expect(p1['deleted_at'], isNotNull);
  });

  test('sincronizarCon respeta LWW: un cambio local mas reciente no se pierde', () async {
    await dbServidor.insert('producto', _producto(id: 'p1', nombre: 'Café'));
    await dbCliente.insert(
      'producto',
      _producto(id: 'p1', nombre: 'Café especial', updatedAt: '2026-06-01T00:00:00.000'),
    );

    await clienteSync().sincronizarCon(peer);

    final p1 = (await dbCliente.query('producto', where: 'id = ?', whereArgs: ['p1'])).first;
    expect(p1['nombre'], 'Café especial',
        reason: 'el cambio local es mas reciente que el del servidor');
  });

  test('un peer con otro esquema se rechaza sin aplicar nada', () async {
    // Un aparato en v2 tenía las ventas dentro de la base principal. Mezclar
    // sus filas con las de v3 no da un error visible: da una contabilidad que
    // no es la de ninguno de los dos.
    final viejo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => viejo.close(force: true));
    viejo.listen((req) {
      req.response
        ..headers.contentType = ContentType.json
        ..write('{"version":1,"esquema":2,"tablas":{"categoria":[],'
            '"producto":[${_jsonProducto()}],"venta":[],"linea_venta":[]}}')
        ..close();
    });

    final peerViejo = PeerVisible(
      deviceId: 'viejo', rol: 'gerente', direccion: '127.0.0.1', puerto: viejo.port,
    );

    await expectLater(
      clienteSync().sincronizarCon(peerViejo),
      throwsA(isA<SyncIncompatible>()),
    );
    expect(await dbCliente.query('producto'), isEmpty,
        reason: 'no puede haberse aplicado ni una fila');
  });
}

String _jsonProducto() =>
    '{"id":"p1","nombre":"Café","imagen":null,"categoria_id":null,'
    '"precio_base":800,"updated_at":"2026-01-01T00:00:00.000","deleted_at":null}';
