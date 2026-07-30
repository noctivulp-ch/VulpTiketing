// Grupo C — sincronización con volumen.
//
// Correr con: flutter test test_estres/sync_volumen_test.dart
//
// Lo que se busca acá no es solo velocidad: el sync es el sistema donde un
// error de volumen puede CORROMPER datos en vez de solo ponerlos lentos, así
// que cada medición va acompañada de una verificación de que las dos bases
// convergen al mismo contenido.
@Timeout(Duration(minutes: 45))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/sync/row_upserter.dart';
import 'package:vulp_tiketing/features/sync/sync_server.dart';

import '_escalera.dart';
import '_generador.dart';

final _tabla = <List<String>>[];
void _anotar(String nivel, String medicion, String valor, [String veredicto = '']) =>
    _tabla.add([nivel, medicion, valor, veredicto]);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() {
    if (_tabla.isEmpty) return;
    final anchos = [0, 1, 2, 3]
        .map((c) => _tabla.map((f) => f[c].length).reduce((a, b) => a > b ? a : b))
        .toList();
    stdout.writeln('\n=== MEDICIONES — grupo C, sincronización ===');
    for (final f in _tabla) {
      stdout.writeln('  ${f[0].padRight(anchos[0])}  ${f[1].padRight(anchos[1])}  '
          '${f[2].padLeft(anchos[2])}  ${f[3]}');
    }
  });

  for (final nivel in nivelesActivos) {
    group('nivel ${nivel.nombre}', () {
      late BaseDeEstres origen;

      setUpAll(() async {
        origen = await baseCon(nivel, log: stdout.writeln);
      });

      tearDownAll(() async => origen.db.close());

      test('tamaño del payload de /sync/exportar', () async {
        // `SyncServer` serializa las 4 tablas COMPLETAS en un solo string JSON
        // en memoria, en cada sync. Esto mide cuánto pesa eso de verdad: es el
        // candidato más claro a quedarse sin memoria en una tablet.
        final rssAntes = rssMb();
        final datos = <String, Object?>{};
        for (final tabla in tablasSincronizables) {
          datos[tabla] = await origen.db.query(tabla);
        }
        final (json, tomo) = await medir(() async => jsonEncode(datos));
        final rssDespues = rssMb();

        final mb = json.length / (1024 * 1024);
        _anotar(nivel.nombre, 'payload sync', '${mb.toStringAsFixed(1)} MB',
            'serializar: ${ms(tomo)}, RSS +${rssDespues - rssAntes} MB');

        expect(json, isNotEmpty);
      });

      test('aplicar un lote grande converge y no corrompe', () async {
        // Se toma un recorte del origen y se aplica sobre una base vacía, que
        // es lo que hace un dispositivo nuevo al entrar al grupo. Un recorte y
        // no todo: el objetivo es medir el costo por fila, y con el nivel techo
        // el volumen completo tarda demasiado para una prueba.
        const filasDelLote = 20000;

        final destino = await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        addTearDown(destino.close);
        await AppDatabase.crearEsquema(destino);

        final categorias = await origen.db.query('categoria');
        final productos = await origen.db.query('producto');
        final ventas = await origen.db.query('venta', limit: filasDelLote ~/ 3);
        final idsVenta = ventas.map((v) => "'${v['id']}'").join(',');
        final lineas = await origen.db.rawQuery(
          'SELECT * FROM linea_venta WHERE venta_id IN ($idsVenta)',
        );

        final upserter = RowUpserter(destino);
        final (_, tomo) = await medir(() async {
          await upserter.aplicar('categoria', categorias);
          await upserter.aplicar('producto', productos);
          await upserter.aplicar('venta', ventas);
          await upserter.aplicar('linea_venta', lineas);
        });

        final filas = categorias.length + productos.length + ventas.length + lineas.length;
        final porFila = tomo.inMicroseconds / filas;
        _anotar(nivel.nombre, 'aplicar $filas filas', ms(tomo),
            '${porFila.toStringAsFixed(0)} µs/fila');

        // Convergencia: lo aplicado tiene que estar completo, no "casi".
        final ventasDestino =
            (await destino.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'] as int;
        final lineasDestino =
            (await destino.rawQuery('SELECT COUNT(*) c FROM linea_venta')).first['c'] as int;
        expect(ventasDestino, equals(ventas.length));
        expect(lineasDestino, equals(lineas.length));

        // Y los importes tienen que ser idénticos: un sync que pierde plata en
        // el camino es peor que un sync lento.
        final totalOrigen = (await origen.db.rawQuery(
          'SELECT SUM(precio_aplicado * cantidad) t FROM linea_venta WHERE venta_id IN ($idsVenta)',
        )).first['t'] as num;
        final totalDestino = (await destino.rawQuery(
          'SELECT SUM(precio_aplicado * cantidad) t FROM linea_venta',
        )).first['t'] as num;
        expect(totalDestino.toDouble(), closeTo(totalOrigen.toDouble(), 0.01));

        expect(tomo, lessThan(umbralCatastrofe),
            reason: 'aplicar $filas filas tardó ${ms(tomo)} en ${nivel.nombre}');
      });

      test('aplicar dos veces el mismo lote es idempotente', () async {
        // Un sync se repite: el mismo peer se vuelve a consultar. Si aplicar dos
        // veces duplicara filas o cambiara importes, el historial se
        // corrompería solo con el uso normal.
        final destino = await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        addTearDown(destino.close);
        await AppDatabase.crearEsquema(destino);

        final ventas = await origen.db.query('venta', limit: 500);
        final idsVenta = ventas.map((v) => "'${v['id']}'").join(',');
        final lineas = await origen.db.rawQuery(
          'SELECT * FROM linea_venta WHERE venta_id IN ($idsVenta)',
        );

        final upserter = RowUpserter(destino);
        Future<void> aplicarTodo() async {
          await upserter.aplicar('categoria', await origen.db.query('categoria'));
          await upserter.aplicar('producto', await origen.db.query('producto'));
          await upserter.aplicar('venta', ventas);
          await upserter.aplicar('linea_venta', lineas);
        }

        await aplicarTodo();
        final totalTrasUna = (await destino.rawQuery(
          'SELECT SUM(precio_aplicado * cantidad) t FROM linea_venta',
        )).first['t'] as num;

        await aplicarTodo();
        final totalTrasDos = (await destino.rawQuery(
          'SELECT SUM(precio_aplicado * cantidad) t FROM linea_venta',
        )).first['t'] as num;
        final lineasTrasDos =
            (await destino.rawQuery('SELECT COUNT(*) c FROM linea_venta')).first['c'] as int;

        expect(lineasTrasDos, equals(lineas.length), reason: 'no se deben duplicar filas');
        expect(totalTrasDos.toDouble(), closeTo(totalTrasUna.toDouble(), 0.01),
            reason: 'el total no puede cambiar al re-aplicar el mismo lote');
      });

      test('un cambio local mas nuevo sobrevive al sync', () async {
        // LWW bajo volumen: el riesgo real no es la lentitud sino que un lote
        // grande pise un cambio local reciente. Si eso pasa, el negocio pierde
        // datos sin enterarse.
        final destino = await databaseFactory.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        addTearDown(destino.close);
        await AppDatabase.crearEsquema(destino);

        final upserter = RowUpserter(destino);
        await upserter.aplicar('categoria', await origen.db.query('categoria'));
        final productos = await origen.db.query('producto');
        await upserter.aplicar('producto', productos);

        // Cambio local POSTERIOR a todo lo remoto.
        final idProducto = productos.first['id'] as String;
        final ahora = DateTime.now().toIso8601String();
        await destino.update(
          'producto',
          {'nombre': 'RENOMBRADO LOCAL', 'updated_at': ahora},
          where: 'id = ?',
          whereArgs: [idProducto],
        );

        // Se re-aplica el lote remoto, que es mas viejo.
        await upserter.aplicar('producto', productos);

        final fila = (await destino.query('producto', where: 'id = ?', whereArgs: [idProducto])).first;
        expect(fila['nombre'], equals('RENOMBRADO LOCAL'),
            reason: 'LWW: el cambio local mas nuevo no puede perderse');
      });
    });
  }
}
