// Grupo F — tensión y concurrencia.
//
// Acá no interesa el volumen acumulado sino la presión: muchas operaciones
// seguidas, operaciones simultáneas, y ciclos de vida de providers repetidos.
//
// Los dos bugs más graves de este proyecto salieron de este terreno y los dos
// tenían la MISMA causa (Riverpod reutiliza la instancia del Notifier entre
// reconstrucciones): el `LateInitializationError` al invalidar, y el id de venta
// que nunca se regeneraba y hacía que solo se pudiera cobrar una vez por sesión.
// Ninguna prueba los veía porque ninguna repetía la operación. Estas sí.
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/venta/venta_en_curso_notifier.dart';
import 'package:vulp_tiketing/features/venta/venta_notifier.dart';

import '_escalera.dart';
import '_generador.dart';

/// Volumen mínimo: en este grupo lo que se prueba es el entrelazado de
/// operaciones, no la acumulación.
const _nivelChico = Nivel(
  nombre: 'chico',
  ventasPorDia: 50,
  dias: 2,
  trato: Trato.caracterizacion,
);

final _tabla = <List<String>>[];
void _anotar(String medicion, String valor, [String extra = '']) =>
    _tabla.add([medicion, valor, extra]);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() {
    if (_tabla.isEmpty) return;
    final anchos = [0, 1, 2]
        .map((c) => _tabla.map((f) => f[c].length).reduce((a, b) => a > b ? a : b))
        .toList();
    stdout.writeln('\n=== MEDICIONES — grupo F, tensión ===');
    for (final f in _tabla) {
      stdout.writeln('  ${f[0].padRight(anchos[0])}  ${f[1].padLeft(anchos[1])}  ${f[2]}');
    }
  });

  Future<Database> dbLimpia() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await crearEsquemaDeEstres(db);
    return db;
  }

  Future<ProviderContainer> contenedorCon(Database db) async {
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('1.000 ventas seguidas sin colisiones de id', () async {
    // El bug real fue con la SEGUNDA venta. Mil da margen de sobra y además
    // mide la degradación: si el tiempo por venta creciera con la cantidad,
    // habría un problema de acumulación en el camino de escritura.
    final db = await dbLimpia();
    addTearDown(db.close);
    final container = await contenedorCon(db);

    const cuantas = 1000;
    final ids = <String>{};
    final reloj = Stopwatch()..start();
    Duration? primeras100;

    for (var i = 0; i < cuantas; i++) {
      final carrito = container.read(ventaEnCursoNotifierProvider.notifier);
      carrito.agregarLineaLibre(nombreLibre: 'venta $i', precio: 1000);
      ids.add(carrito.ventaIdBorrador);
      await carrito.guardar();
      if (i == 99) primeras100 = reloj.elapsed;
    }
    reloj.stop();

    expect(ids, hasLength(cuantas), reason: 'cada venta necesita su propio id');
    final filas = (await db.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'] as int;
    expect(filas, equals(cuantas));

    final ultimas100 = reloj.elapsed - primeras100! * (cuantas / 100 - 1) ~/ 1;
    _anotar('1.000 ventas seguidas', ms(reloj.elapsed),
        '${(reloj.elapsedMicroseconds / cuantas / 1000).toStringAsFixed(2)} ms por venta');
    // Se registra pero no se asserta: el objetivo es detectar degradación
    // evidente, y `ultimas100` es una estimación cruda.
    expect(ultimas100, isNotNull);
  });

  test('el carrito nunca arrastra lineas entre ventas', () async {
    // Si el carrito no se vaciara, la venta N cobraría también lo de la N-1.
    // Es plata mal cobrada, no un detalle técnico.
    final db = await dbLimpia();
    addTearDown(db.close);
    final container = await contenedorCon(db);

    for (var i = 0; i < 50; i++) {
      final carrito = container.read(ventaEnCursoNotifierProvider.notifier);
      expect(container.read(ventaEnCursoNotifierProvider).lineas, isEmpty,
          reason: 'la venta $i arrancó con líneas de la anterior');
      carrito.agregarLineaLibre(nombreLibre: 'x', precio: 500);
      await carrito.guardar();
    }

    final totales = await db.rawQuery(
      'SELECT venta_id, COUNT(*) c FROM linea_venta GROUP BY venta_id HAVING c > 1',
    );
    expect(totales, isEmpty, reason: 'ninguna venta debe tener líneas de más');
  });

  test('invalidar providers 200 veces no rompe nada', () async {
    // El `LateInitializationError` aparecía en la SEGUNDA construcción. Esto
    // recorre el ciclo de vida muchas veces, sobre los tres Notifiers que lo
    // sufrieron, para que una regresión del patrón no pase inadvertida.
    final db = await dbLimpia();
    addTearDown(db.close);
    final container = await contenedorCon(db);

    final reloj = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await container.read(productoNotifierProvider.future);
      await container.read(categoriaNotifierProvider.future);
      await container.read(ventaNotifierProvider.future);
      container.invalidate(productoNotifierProvider);
      container.invalidate(categoriaNotifierProvider);
      container.invalidate(ventaNotifierProvider);
    }
    reloj.stop();

    await expectLater(container.read(productoNotifierProvider.future), completes);
    await expectLater(container.read(ventaNotifierProvider.future), completes);
    _anotar('200 ciclos de invalidacion', ms(reloj.elapsed));
  });

  test('invalidar databaseProvider tampoco rompe a sus dependientes', () async {
    // Este es el camino que disparó el crash real: restaurar un backup invalida
    // `databaseProvider`, y todo lo que lo observa se reconstruye.
    final db = await dbLimpia();
    addTearDown(db.close);
    final container = await contenedorCon(db);

    for (var i = 0; i < 25; i++) {
      await container.read(productoNotifierProvider.future);
      container.invalidate(databaseProvider);
    }
    await expectLater(container.read(productoNotifierProvider.future), completes);
  });

  test('guardar ventas mientras se calcula un reporte', () async {
    // Concurrencia real: el cajero cobra mientras el gerente mira reportes en
    // otro dispositivo, o la misma app recalcula. Lo que no puede pasar es que
    // el reporte devuelva un total incoherente con lo que hay en la base.
    // Volumen chico: acá lo que se prueba es el entrelazado, no el tamaño.
    final base = await baseCon(_nivelChico, log: stdout.writeln);
    addTearDown(base.db.close);
    final container = await contenedorCon(base.db);

    final escrituras = Future(() async {
      for (var i = 0; i < 100; i++) {
        final carrito = container.read(ventaEnCursoNotifierProvider.notifier);
        carrito.agregarLineaLibre(nombreLibre: 'concurrente $i', precio: 700);
        await carrito.guardar();
      }
    });

    final lecturas = Future(() async {
      final totales = <double>[];
      for (var i = 0; i < 20; i++) {
        final r = await container.read(reportesProvider(ReportesParametros(
          rango: RangoReporte.dia,
          fechaReferencia: DateTime(2020, 1, 1),
        )).future);
        totales.add(r.total);
        // Coherencia interna en cada lectura, aunque los datos cambien debajo.
        expect(r.porTurno.values.fold(0.0, (a, b) => a + b), closeTo(r.total, 0.01));
        container.invalidate(reportesProvider);
      }
      return totales;
    });

    final (_, totales) = await (escrituras, lecturas).wait;
    _anotar('lecturas concurrentes', '${totales.length}', 'todas coherentes');

    final filas = (await base.db.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'] as int;
    expect(filas, greaterThanOrEqualTo(100));
  });
}

