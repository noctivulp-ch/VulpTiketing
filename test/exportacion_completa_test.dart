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
    await for (final lote in ventasDelRangoPorLotes(db, LibroVentasService(directorio: dir.path), params, lote: 200)) {
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
    await for (final lote in ventasDelRangoPorLotes(db, LibroVentasService(directorio: dir.path), params, lote: 200)) {
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
      lotes: ventasDelRangoPorLotes(db, LibroVentasService(directorio: dir.path), params, lote: 200),
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
      lotes: ventasDelRangoPorLotes(db, LibroVentasService(directorio: dir.path), params, lote: 50),
    );

    expect(await destino.length(), greaterThan(cuantas * 40));
  });

  test('la pantalla SÍ sigue con su tope: son cosas distintas', () async {
    final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
    addTearDown(c.dispose);

    final detalle = await c.read(detalleRangoProvider(PaginaDetalle(params)).future);

    expect(detalle.ventas, hasLength(limiteDetalleRango));
    expect(detalle.totalVentas, cuantas);
    expect(detalle.truncado, isTrue);
  });

  group('el detalle de pantalla pagina', () {
    ProviderContainer contenedor() {
      final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
      addTearDown(c.dispose);
      return c;
    }

    test('cada tanda trae las siguientes, sin repetir', () async {
      // 700 ventas en tandas de 300: 300 + 300 + 100.
      final c = contenedor();
      final vistas = <String>{};
      var ultima = 0;

      for (var pagina = 0; pagina < 3; pagina++) {
        final tanda = await c.read(
          detalleRangoProvider(PaginaDetalle(params, pagina: pagina)).future,
        );
        for (final v in tanda.ventas) {
          expect(vistas.add(v.venta.id), isTrue, reason: '${v.venta.id} vino dos veces');
        }
        ultima = tanda.ventas.length;
      }

      expect(vistas, hasLength(cuantas), reason: 'entre las tres tandas están todas');
      expect(ultima, cuantas - limiteDetalleRango * 2, reason: 'la última va incompleta');
    });

    test('sabe dónde está parada y si queda algo', () async {
      final c = contenedor();

      final primera = await c.read(detalleRangoProvider(PaginaDetalle(params)).future);
      expect(primera.pagina, 0);
      expect(primera.paginas, 3);
      expect(primera.hayAnterior, isFalse);
      expect(primera.haySiguiente, isTrue);
      expect(primera.desplazamiento, 0);

      final ultima = await c.read(detalleRangoProvider(PaginaDetalle(params, pagina: 2)).future);
      expect(ultima.hayAnterior, isTrue);
      expect(ultima.haySiguiente, isFalse, reason: 'no hay una cuarta tanda');
      expect(ultima.desplazamiento, limiteDetalleRango * 2);
    });

    test('un período que cabe entero tiene una sola página', () async {
      final c = contenedor();
      final detalle = await c.read(
        detalleRangoProvider(
          PaginaDetalle(
            ReportesParametros(rango: RangoReporte.dia, fechaReferencia: DateTime(2026, 1, 1)),
          ),
        ).future,
      );

      expect(detalle.paginas, 1);
      expect(detalle.haySiguiente, isFalse);
      expect(detalle.truncado, isFalse);
    });

    test('cambiar de página NO recalcula el reporte general', () async {
      // Es la razón de que la página viva en su propia clave y no en
      // `ReportesParametros`: totales, turnos y rankings no dependen de qué
      // tanda se esté mirando, y recalcularlos al pasar de página sería pagar
      // la consulta cara por nada.
      final c = contenedor();
      final antes = await c.read(reportesProvider(params).future);

      await c.read(detalleRangoProvider(PaginaDetalle(params, pagina: 1)).future);
      final despues = c.read(reportesProvider(params)).valueOrNull;

      expect(identical(antes, despues), isTrue, reason: 'el reporte no se volvió a calcular');
    });
  });
}
