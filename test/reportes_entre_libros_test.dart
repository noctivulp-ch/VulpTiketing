import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/reportes/periodos_con_datos_provider.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/venta/lectura_de_libros.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Reportes a través de un libro CERRADO.
///
/// Tras ~365 días con ventas el libro se cierra y el siguiente se abre. Hasta
/// esta prueba, todo lo que consultaba ventas miraba solo el libro adjunto —el
/// abierto—, así que el año anterior, intacto en su archivo, habría salido
/// como "sin ventas" en Reportes, en el calendario y en la exportación. Nadie
/// lo había visto porque ningún aparato llevaba un año vendiendo.
///
/// Acá se cierra un libro a mano (la cuenta de días se pone al tope y se
/// vende un día nuevo) y se pide un mes que cruza los dos.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;
  late LibroVentasService libros;
  late ProviderContainer c;

  Future<void> vender(String id, DateTime cuando, double precio, {String producto = 'casado'}) async {
    await libros.prepararPara(db, cuando);
    await db.insert('venta', {
      'id': id,
      'fecha_hora': cuando.toIso8601String(),
      'estado': 'activa',
      'updated_at': cuando.toIso8601String(),
    });
    await db.insert('linea_venta', {
      'id': 'l-$id',
      'venta_id': id,
      'producto_id': producto,
      'precio_aplicado': precio,
      'cantidad': 1,
      'updated_at': cuando.toIso8601String(),
    });
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-entre-libros');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await db.insert('producto', {
      'id': 'casado',
      'nombre': 'Casado',
      'precio_base': 3000,
      'updated_at': DateTime(2026).toIso8601String(),
    });
    libros = LibroVentasService(directorio: dir.path);
    await libros.adjuntarAbierto(db);

    // Marzo de 2026: dos ventas en el libro A. Después el libro "se llena" y la
    // venta del 20 de marzo abre el libro B.
    await vender('a1', DateTime(2026, 3, 5, 10), 3000);
    await vender('a2', DateTime(2026, 3, 12, 15), 2500);
    final abierto = (await libros.libroAbierto(db))!;
    await db.update('libro_ventas', {'dias_con_ventas': diasPorLibro}, where: 'id = ?', whereArgs: [abierto.id]);
    await vender('b1', DateTime(2026, 3, 20, 9), 4000);
    await vender('b2', DateTime(2026, 3, 28, 18), 1000);

    c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        libroVentasServiceProvider.overrideWith((ref) async => libros),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('el libro A quedó cerrado y el B abierto, con las ventas repartidas', () async {
    final todos = await libros.todos(db);
    // El índice ordena por `fecha_inicio`, que es el día de CREACIÓN del
    // archivo: el libro A se creó "hoy" y recibió ventas de marzo. Por eso
    // los reportes no pueden fiarse del índice para saber qué cubre cada uno.
    expect(todos.where((l) => l.cerrado), hasLength(1));
    expect(todos.where((l) => !l.cerrado), hasLength(1));
    // El adjunto es B: solo dos ventas a la vista sin el lector.
    expect(await db.query('venta'), hasLength(2));
  });

  test('el reporte del mes suma los dos libros', () async {
    final reporte = await c.read(
      reportesProvider(ReportesParametros(rango: RangoReporte.mes, fechaReferencia: DateTime(2026, 3, 1))).future,
    );
    expect(reporte.total, 3000 + 2500 + 4000 + 1000);
    expect(reporte.masVendidos.single.cantidad, 4, reason: 'el ranking se funde por producto');
  });

  test('un día del libro cerrado sigue teniendo su detalle', () async {
    final reporte = await c.read(
      reportesProvider(ReportesParametros(rango: RangoReporte.dia, fechaReferencia: DateTime(2026, 3, 5))).future,
    );
    expect(reporte.total, 3000);
    final ventas = reporte.ventasPorTurno.values.expand((v) => v).toList();
    expect(ventas.single.lineas.single.descripcion, 'Casado');
  });

  test('el detalle paginado del mes recorre los dos libros en orden, sin repetir', () async {
    limiteDetalleRango = 3;
    addTearDown(() => limiteDetalleRango = 300);
    final params = ReportesParametros(rango: RangoReporte.mes, fechaReferencia: DateTime(2026, 3, 1));

    final pagina0 = await c.read(detalleRangoProvider(PaginaDetalle(params)).future);
    final pagina1 = await c.read(detalleRangoProvider(PaginaDetalle(params, pagina: 1)).future);

    expect(pagina0.totalVentas, 4);
    expect(pagina0.ventas.map((v) => v.venta.id), ['b2', 'b1', 'a2'], reason: 'más recientes primero, cruzando al libro A');
    expect(pagina1.ventas.map((v) => v.venta.id), ['a1']);
    expect(pagina0.haySiguiente, isTrue);
    expect(pagina1.haySiguiente, isFalse);
  });

  test('la exportación por lotes trae las cuatro, del libro viejo al nuevo', () async {
    final params = ReportesParametros(rango: RangoReporte.mes, fechaReferencia: DateTime(2026, 3, 1));
    final ids = <String>[];
    await for (final lote in ventasDelRangoPorLotes(db, libros, params, lote: 3)) {
      ids.addAll(lote.map((v) => v.venta.id));
    }
    expect(ids, ['a1', 'a2', 'b1', 'b2']);
  });

  test('el calendario marca los días del libro cerrado', () async {
    final periodos = await c.read(periodosConDatosProvider(2026).future);
    expect(periodos.dias, {'2026-03-05', '2026-03-12', '2026-03-20', '2026-03-28'});
    expect(await c.read(aniosConVentasProvider.future), {2026});
  });

  test('el libro cerrado queda adjunto con su alias y no se vuelve a adjuntar', () async {
    final lector = LectorDeLibros(db, () async => libros);
    final cerrado = (await libros.todos(db)).firstWhere((l) => l.cerrado);
    final alias = await lector.esquemaDe(cerrado);
    expect(alias, LectorDeLibros.aliasDe(cerrado));
    expect(await lector.esquemaDe(cerrado), alias);
    final adjuntos = (await db.rawQuery('PRAGMA database_list')).map((f) => f['name']).toList();
    expect(adjuntos.where((a) => a == alias), hasLength(1));
  });
}
