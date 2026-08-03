import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Libros de ventas rodantes — decisión 0025.
///
/// Lo que se prueba acá es la propiedad que hace valioso el modelo: las ventas
/// **nunca se mueven ni se borran**. Un libro se llena, se cierra, y el
/// siguiente arranca vacío. Si alguna de estas pruebas falla, el diseño perdió
/// justamente lo que lo hacía seguro.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database principal;
  late LibroVentasService servicio;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-libros');
    principal = await databaseFactory.openDatabase(
      p.join(dir.path, 'principal.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(principal);
    servicio = LibroVentasService(directorio: dir.path);
  });

  tearDown(() async {
    await principal.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Guarda una venta con una línea, pasando por la rotación como hace la app.
  Future<void> vender(DateTime cuando, {double precio = 1000}) async {
    await servicio.prepararPara(principal, cuando);
    final id = 'v-${cuando.toIso8601String()}';
    await principal.insert('venta', {
      'id': id,
      'fecha_hora': cuando.toIso8601String(),
      'estado': 'activa',
      'updated_at': cuando.toIso8601String(),
    });
    await principal.insert('linea_venta', {
      'id': 'l-$id',
      'venta_id': id,
      'nombre_libre': 'algo',
      'precio_aplicado': precio,
      'cantidad': 1,
      'updated_at': cuando.toIso8601String(),
    });
  }

  test('sin ventas no hay ningun libro ni archivo suelto', () async {
    expect(await servicio.libroAbierto(principal), isNull);
    final archivos = dir
        .listSync()
        .map((e) => p.basename(e.path))
        .where((n) => n.startsWith('ventas-'));
    expect(archivos, isEmpty, reason: 'una instalación nueva no debe crear libros');
  });

  test('la primera venta crea el libro y la escritura aterriza en su archivo', () async {
    await vender(DateTime(2026, 3, 10, 12));

    final libro = await servicio.libroAbierto(principal);
    expect(libro, isNotNull);
    expect(libro!.diasConVentas, equals(1));
    expect(libro.cerrado, isFalse);
    expect(libro.archivo, equals('ventas-2026-03-10.db'));

    // La venta se consultó y escribió SIN calificar la base: tiene que estar en
    // el archivo del libro, no en la principal. Es lo que hace que el resto del
    // código no haya tenido que cambiar.
    final enElArchivo = await databaseFactory.openDatabase(
      p.join(dir.path, libro.archivo),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final cuantas = (await enElArchivo.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'];
    await enElArchivo.close();
    expect(cuantas, equals(1));

    // Y NO debe existir en la base principal.
    final enPrincipal = await principal.rawQuery(
      "SELECT COUNT(*) c FROM main.sqlite_master WHERE type='table' AND name='venta'",
    );
    expect(
      enPrincipal.first['c'],
      equals(0),
      reason: 'venta no puede existir en la base principal',
    );
  });

  test('varias ventas del mismo dia no suman dias', () async {
    final dia = DateTime(2026, 3, 10);
    await vender(dia.add(const Duration(hours: 9)));
    await vender(dia.add(const Duration(hours: 13)));
    await vender(dia.add(const Duration(hours: 19)));

    final libro = await servicio.libroAbierto(principal);
    expect(
      libro!.diasConVentas,
      equals(1),
      reason: 'un libro se mide en dias CON ventas, no en cantidad de ventas',
    );
  });

  test('los dias sin ventas no gastan el libro', () async {
    // El negocio cierra dos meses entre una venta y la siguiente.
    await vender(DateTime(2026, 1, 10, 12));
    await vender(DateTime(2026, 3, 15, 12));

    final libro = await servicio.libroAbierto(principal);
    expect(
      libro!.diasConVentas,
      equals(2),
      reason: 'entre enero y marzo hay 64 dias de calendario, pero solo 2 con ventas',
    );
  });

  test('al dia 366 se cierra el libro y la venta abre uno nuevo', () async {
    // 365 dias con ventas, uno por dia.
    final inicio = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < diasPorLibro; i++) {
      await vender(inicio.add(Duration(days: i)));
    }

    final lleno = await servicio.libroAbierto(principal);
    expect(lleno!.diasConVentas, equals(diasPorLibro));
    expect(lleno.cerrado, isFalse, reason: 'con 365 justos todavia esta abierto');

    // La venta del dia 366 es la que dispara la rotacion.
    await vender(inicio.add(const Duration(days: diasPorLibro)));

    final libros = await servicio.todos(principal);
    expect(libros, hasLength(2));

    final cerrado = libros.firstWhere((l) => l.cerrado);
    final abierto = libros.firstWhere((l) => !l.cerrado);

    expect(cerrado.diasConVentas, equals(diasPorLibro));
    expect(cerrado.fechaFin, isNotNull);
    expect(
      cerrado.archivo,
      contains('_'),
      reason: 'un libro cerrado se renombra a inicio_final.db',
    );
    expect(File(p.join(dir.path, cerrado.archivo)).existsSync(), isTrue);

    expect(
      abierto.diasConVentas,
      equals(1),
      reason: 'el libro nuevo arranca con la venta que lo abrio',
    );
  });

  test('nada se pierde al rotar: cada venta esta en exactamente un libro', () async {
    final inicio = DateTime(2026, 1, 1, 12);
    const total = diasPorLibro + 5;
    for (var i = 0; i < total; i++) {
      await vender(inicio.add(Duration(days: i)), precio: 100 + i.toDouble());
    }

    final libros = await servicio.todos(principal);
    expect(libros, hasLength(2));

    var contadas = 0;
    var suma = 0.0;
    for (final libro in libros) {
      final db = await databaseFactory.openDatabase(
        p.join(dir.path, libro.archivo),
        options: OpenDatabaseOptions(singleInstance: false),
      );
      contadas += (await db.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'] as int;
      final s =
          (await db.rawQuery(
                'SELECT SUM(precio_aplicado * cantidad) t FROM linea_venta',
              )).first['t']
              as num?;
      suma += s?.toDouble() ?? 0;
      await db.close();
    }

    // La suma esperada: 100+0, 100+1, ... 100+(total-1)
    final esperada = List.generate(total, (i) => 100 + i).reduce((a, b) => a + b);
    expect(contadas, equals(total), reason: 'ninguna venta puede perderse al rotar');
    expect(
      suma,
      closeTo(esperada.toDouble(), 0.01),
      reason: 'ningun importe puede perderse al rotar',
    );
  });

  test('un libro cerrado se puede leer sin restaurarlo, junto con el abierto', () async {
    final inicio = DateTime(2026, 1, 1, 12);
    for (var i = 0; i <= diasPorLibro; i++) {
      await vender(inicio.add(Duration(days: i)), precio: 1000);
    }

    final libros = await servicio.todos(principal);
    final cerrado = libros.firstWhere((l) => l.cerrado);

    // Lectura en caliente: se adjunta el libro cerrado junto al abierto y se
    // consultan los dos en UNA sentencia. Es la capacidad que justifica que el
    // formato sea SQLite y no uno propio.
    await principal.execute("ATTACH DATABASE '${p.join(dir.path, cerrado.archivo)}' AS historico");
    final r = await principal.rawQuery('''
      SELECT SUM(total) t FROM (
        SELECT precio_aplicado * cantidad AS total FROM linea_venta
        UNION ALL
        SELECT precio_aplicado * cantidad AS total FROM historico.linea_venta
      )
    ''');
    await principal.execute('DETACH DATABASE historico');

    expect(
      (r.first['t'] as num).toDouble(),
      closeTo((diasPorLibro + 1) * 1000.0, 0.01),
      reason: 'la consulta debe sumar el libro abierto y el cerrado',
    );
  });

  test('la migracion v2 a v3 mueve las ventas sin perder nada', () async {
    // Base v2: las ventas todavia viven en la principal.
    final rutaVieja = p.join(dir.path, 'vieja.db');
    final vieja = await databaseFactory.openDatabase(
      rutaVieja,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await vieja.execute(AppDatabase.esquema[0]); // categoria
    await vieja.execute(AppDatabase.esquema[1]); // producto
    await aplicarEsquemaLibro(vieja); // venta y linea_venta, como en v2

    for (var i = 0; i < 5; i++) {
      final f = DateTime(2026, 2, 1 + i, 12).toIso8601String();
      await vieja.insert('venta', {
        'id': 'v$i',
        'fecha_hora': f,
        'estado': 'activa',
        'updated_at': f,
      });
      await vieja.insert('linea_venta', {
        'id': 'l$i',
        'venta_id': 'v$i',
        'nombre_libre': 'x',
        'precio_aplicado': 700.0,
        'cantidad': 2,
        'updated_at': f,
      });
    }

    await AppDatabase.migrarVentasALibro(vieja, dir.path);

    // Las tablas ya no estan en la principal…
    final quedan = await vieja.rawQuery(
      "SELECT COUNT(*) c FROM sqlite_master WHERE type='table' AND name IN ('venta','linea_venta')",
    );
    expect(quedan.first['c'], equals(0));

    // …y el libro tiene todo, con los dias bien contados.
    final servicioMigrado = LibroVentasService(directorio: dir.path);
    final libro = await servicioMigrado.libroAbierto(vieja);
    expect(libro, isNotNull);
    expect(libro!.diasConVentas, equals(5));

    final libroDb = await databaseFactory.openDatabase(
      p.join(dir.path, libro.archivo),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final ventas = (await libroDb.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'];
    final suma =
        (await libroDb.rawQuery(
              'SELECT SUM(precio_aplicado * cantidad) t FROM linea_venta',
            )).first['t']
            as num;
    await libroDb.close();
    await vieja.close();

    expect(ventas, equals(5));
    expect(suma.toDouble(), closeTo(5 * 700 * 2, 0.01));
  });
}
