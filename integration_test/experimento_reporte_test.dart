// Experimento: por qué el reporte del AÑO cuesta 200 ms y qué lo bajaría.
//
//   flutter drive --driver=test_driver/banco_driver.dart \
//     --target=integration_test/experimento_reporte_test.dart --profile -d <id>
//
// No es una prueba de regresión: es un banco de pruebas para comparar opciones
// con el mismo volumen y el mismo aparato, que es la única forma de saber cuál
// gana. Corre después del banco, que es quien siembra los datos.
//
// Sin `EXPLAIN QUERY PLAN`: el driver de sqflite en Android devuelve
// `SQLITE_ROW` como error al ejecutarlo, así que acá se compara midiendo. Es
// más lento de escribir pero responde la pregunta que importa —cuál gana— en
// vez de la intermedia.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'siembra.dart';

const _rangoAnio = "v.estado = 'activa' AND v.fecha_hora >= ? AND v.fecha_hora < ?";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opciones para el reporte del año', (tester) async {
    final db = await prepararBaseDePruebas();
    final ahora = DateTime.now();
    final desde = DateTime(ahora.year).toIso8601String();
    final hasta = DateTime(ahora.year + 1).toIso8601String();
    final args = [desde, hasta];

    Future<double> medir(String etiqueta) async {
      Future<void> reporte() async {
        await db.rawQuery('''
          SELECT SUM(lv.precio_aplicado * lv.cantidad) AS total
          FROM linea_venta lv
          JOIN venta v ON v.id = lv.venta_id
          WHERE $_rangoAnio
        ''', args);
        await db.rawQuery('''
          SELECT lv.producto_id AS id, SUM(lv.cantidad) AS cantidad
          FROM linea_venta lv
          JOIN venta v ON v.id = lv.venta_id
          LEFT JOIN producto p ON p.id = lv.producto_id
          WHERE $_rangoAnio AND lv.producto_id IS NOT NULL
          GROUP BY lv.producto_id
          ORDER BY cantidad DESC
        ''', args);
      }

      await reporte();
      final reloj = Stopwatch()..start();
      for (var i = 0; i < 3; i++) {
        await reporte();
      }
      reloj.stop();
      final ms = reloj.elapsedMilliseconds / 3;
      // ignore: avoid_print
      print('EXPERIMENTO\t$etiqueta\t$ms');
      return ms;
    }

    await medir('1 · como está');

    // Opción A — ANALYZE: le da estadísticas al planificador. Es lo más barato
    // que existe (no cambia el esquema ni el código) y a veces basta.
    await db.execute('ANALYZE libro');
    await medir('2 · tras ANALYZE');

    // Opción B — índice cubriente: si el índice ya trae producto_id, cantidad y
    // precio, el JOIN no necesita leer la fila de linea_venta. Cuesta espacio
    // en disco y hace un poco más lenta cada venta que se graba.
    // `libro.` explícito: a diferencia de un SELECT o un INSERT, que resuelven
    // el nombre contra la base adjunta cuando la tabla no está en `main`,
    // CREATE INDEX se planta en `main` y falla con "no such table".
    await db.execute('''
      CREATE INDEX IF NOT EXISTS libro.idx_lv_cubriente
      ON linea_venta(venta_id, producto_id, cantidad, precio_aplicado)
    ''');
    await db.execute('ANALYZE libro');
    await medir('3 · con índice cubriente');

    // Opción C — el índice cubriente SIN las estadísticas, para saber cuál de
    // los dos cambios es el que aporta.
    await db.execute('DROP TABLE IF EXISTS libro.sqlite_stat1');
    await medir('4 · cubriente sin ANALYZE');

    // Se deshace: este archivo mide, no migra. Si el índice gana, entra por el
    // esquema y con su decisión escrita.
    await db.execute('DROP INDEX IF EXISTS libro.idx_lv_cubriente');
    await medir('5 · vuelta al estado inicial');

    // Opción D — mmap: dejar que SQLite lea el archivo mapeado en memoria en
    // vez de por llamadas al sistema. No cambia el esquema ni una línea de
    // consulta; si diera, sería lo más barato de todo.
    // `rawQuery` y no `execute`: un PRAGMA que DEVUELVE valor muere por
    // `execute` en Android con "Queries can be performed using query or
    // rawQuery methods only".
    await db.rawQuery('PRAGMA mmap_size = 67108864');
    await medir('6 · con mmap 64 MB');
    await db.rawQuery('PRAGMA mmap_size = 0');

    // Opción E — sin JOIN: la fecha, denormalizada en la propia línea. Es la de
    // más recorrido porque elimina el JOIN entero, y también la más cara: una
    // columna redundante que hay que mantener en cada venta y una migración de
    // esquema. Se prueba sobre una tabla aparte para no tocar la de verdad.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS libro.lv_plana(
        producto_id TEXT,
        cantidad INTEGER NOT NULL,
        precio_aplicado REAL NOT NULL,
        fecha_hora TEXT NOT NULL
      )
    ''');
    await db.execute('DELETE FROM lv_plana');
    await db.execute('''
      INSERT INTO lv_plana(producto_id, cantidad, precio_aplicado, fecha_hora)
      SELECT lv.producto_id, lv.cantidad, lv.precio_aplicado, v.fecha_hora
      FROM linea_venta lv JOIN venta v ON v.id = lv.venta_id
      WHERE v.estado = 'activa'
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS libro.idx_lv_plana
      ON lv_plana(fecha_hora, producto_id)
    ''');

    Future<void> reportePlano() async {
      await db.rawQuery('''
        SELECT SUM(precio_aplicado * cantidad) AS total
        FROM lv_plana WHERE fecha_hora >= ? AND fecha_hora < ?
      ''', args);
      await db.rawQuery('''
        SELECT producto_id AS id, SUM(cantidad) AS cantidad
        FROM lv_plana
        WHERE fecha_hora >= ? AND fecha_hora < ? AND producto_id IS NOT NULL
        GROUP BY producto_id ORDER BY cantidad DESC
      ''', args);
    }

    await reportePlano();
    final relojPlano = Stopwatch()..start();
    for (var i = 0; i < 3; i++) {
      await reportePlano();
    }
    relojPlano.stop();
    // ignore: avoid_print
    print('EXPERIMENTO\t7 · sin JOIN (fecha denormalizada)\t${relojPlano.elapsedMilliseconds / 3}');

    await db.execute('DROP TABLE IF EXISTS libro.lv_plana');

    final tamano = await db.rawQuery('PRAGMA libro.page_count');
    // ignore: avoid_print
    print('EXPERIMENTO\tpáginas del libro\t${tamano.first.values.first}');
  });
}
