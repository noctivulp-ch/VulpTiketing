import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/reportes/reporte_export_service.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Un informe exportado lleva **todas** las ventas del período.
///
/// El tope de `limiteDetalleRango` es para la PANTALLA: nadie desplaza 5.000
/// filas en un teléfono. Al exportar era un error — el archivo salía con las
/// 300 más recientes y una nota de disculpa, y eso no se le manda a un contador.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  /// Más del doble del tope de pantalla, para que recortar se note.
  const cuantas = 700;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-export-completa');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await aplicarEsquemaLibro(db);

    await db.insert('producto', {
      'id': 'p1',
      'nombre': 'Casado con pollo',
      'precio_base': 2500.0,
      'updated_at': DateTime(2026).toIso8601String(),
    });

    final lote = db.batch();
    for (var i = 0; i < cuantas; i++) {
      final cuando = DateTime(2026, 1 + (i % 12), 1 + (i % 28), 8 + (i % 12));
      lote.insert('venta', {
        'id': 'v$i',
        'fecha_hora': cuando.toIso8601String(),
        'estado': 'activa',
        'updated_at': cuando.toIso8601String(),
      });
      lote.insert('linea_venta', {
        'id': 'l$i',
        'venta_id': 'v$i',
        'producto_id': 'p1',
        'precio_aplicado': 2500.0,
        'cantidad': 2,
        'updated_at': cuando.toIso8601String(),
      });
    }
    await lote.commit(noResult: true);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final params = ReportesParametros(
    rango: RangoReporte.anio,
    fechaReferencia: DateTime(2026, 6, 15),
  );

  test('los lotes traen TODAS las ventas del período, sin tope', () async {
    var total = 0;
    var lotes = 0;
    await for (final lote in ventasDelRangoPorLotes(db, params, lote: 200)) {
      total += lote.length;
      lotes++;
    }

    expect(total, cuantas, reason: 'el tope de pantalla no puede aplicarse al exportar');
    expect(lotes, greaterThan(1), reason: 'va por lotes, no de una');
  });

  test('los lotes no repiten ni se saltan ninguna venta', () async {
    // Paginar por OFFSET repite filas si el orden no es estable. Se comprueba
    // con los ids, no con el conteo: 700 duplicados y 700 distintos suman igual.
    final vistas = <String>{};
    await for (final lote in ventasDelRangoPorLotes(db, params, lote: 200)) {
      for (final v in lote) {
        expect(vistas.add(v.venta.id), isTrue, reason: '${v.venta.id} vino dos veces');
      }
    }
    expect(vistas, hasLength(cuantas));
  });

  test('el CSV exportado tiene una fila por línea de TODAS las ventas', () async {
    final destino = File(p.join(dir.path, 'reporte.csv'));

    final escritas = await const ReporteExportService().escribirCsvPorLotes(
      destino: destino,
      titulo: 'Ventas del año · 2026',
      total: 3500000,
      lotes: ventasDelRangoPorLotes(db, params, lote: 200),
    );

    expect(escritas, cuantas);
    final lineas = (await destino.readAsString()).split('\r\n');
    // Cabecera del detalle + una fila por línea de venta.
    expect(lineas.where((l) => l.contains('Casado con pollo')), hasLength(cuantas));
    expect(lineas.any((l) => l.startsWith('"Ventas","$cuantas"')), isTrue);
    // 700 ventas × 2 unidades.
    expect(lineas.any((l) => l.startsWith('"Artículos","${cuantas * 2}"')), isTrue);
  });

  test('el CSV completo no depende de que el período quepa en memoria', () async {
    // La prueba de que se escribe a medida: el archivo ya tiene contenido antes
    // de que termine el último lote. Si se construyera entero en memoria, esto
    // no se podría comprobar sin agotar la RAM a propósito.
    final destino = File(p.join(dir.path, 'grande.csv'));
    await const ReporteExportService().escribirCsvPorLotes(
      destino: destino,
      titulo: 'Ventas del año · 2026',
      total: 3500000,
      lotes: ventasDelRangoPorLotes(db, params, lote: 50),
    );

    expect(await destino.length(), greaterThan(cuantas * 40));
  });

  test('la pantalla SÍ sigue con su tope: son cosas distintas', () async {
    final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
    addTearDown(c.dispose);

    final detalle = await c.read(detalleRangoProvider(params).future);

    expect(detalle.ventas, hasLength(limiteDetalleRango));
    expect(detalle.totalVentas, cuantas);
    expect(detalle.truncado, isTrue);
  });
}
