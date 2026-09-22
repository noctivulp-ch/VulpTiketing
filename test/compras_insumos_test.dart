import 'dart:io';

import 'package:costeo/costeo.dart' as c;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/costeo/compra_insumo_model.dart';
import 'package:vulp_tiketing/features/costeo/config_costeo_model.dart';
import 'package:vulp_tiketing/features/costeo/compra_insumo_notifier.dart';
import 'package:vulp_tiketing/features/costeo/costeo_notifiers.dart';
import 'package:vulp_tiketing/features/costeo/costeo_provider.dart';
import 'package:vulp_tiketing/features/costeo/costo_de_insumos_provider.dart';
import 'package:vulp_tiketing/features/costeo/insumo_model.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/sync/sync_server.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// El libro de compras de insumos (0041): el insumo se registra una vez y
/// cada compra es una entrada; el costo sale de las compras.
///
/// Lo que se vigila: que el promedio ponderado sea el de la fórmula y no
/// "el último precio"; que sin compras recientes se caiga a la última y sin
/// ninguna al arranque, diciendo cuál; que un libro viejo gane la tabla al
/// adjuntarse; y que las compras crucen libros como las ventas.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;
  late LibroVentasService libros;
  late ProviderContainer container;

  final harina = InsumoRegistro(
    id: 'harina',
    nombre: 'Harina',
    unidadBase: c.UnidadBase.gramo,
    contenidoPorCompra: 1000,
    precioCompra: 900, // arranque: 0,90/g
    updatedAt: DateTime(2026),
  );

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-compras');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    libros = LibroVentasService(directorio: dir.path);
    await libros.adjuntarAbierto(db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        libroVentasServiceProvider.overrideWith((ref) async => libros),
      ],
    );
    await container.read(insumoNotifierProvider.notifier).crear(harina);
  });

  tearDown(() async {
    container.dispose();
    await libros.desadjuntar(db);
    await db.close();
    dir.deleteSync(recursive: true);
  });

  CompraInsumo compra(String id, DateTime fecha, {double presentaciones = 1, required double contenido, required double pagado}) =>
      CompraInsumo(id: id, insumoId: 'harina', fecha: fecha, presentaciones: presentaciones, contenido: contenido, pagado: pagado, updatedAt: fecha);

  test('la tabla está en el libro nuevo, en el sync, y un libro viejo la gana al adjuntarse', () async {
    expect(await db.query('compra_insumo'), isEmpty);
    expect(tablasSincronizables, contains('compra_insumo'));

    // Un libro escrito antes de 0041: solo venta y linea_venta.
    final viejo = await databaseFactory.openDatabase(p.join(dir.path, 'libro-viejo.db'), options: OpenDatabaseOptions(singleInstance: false));
    await viejo.execute("CREATE TABLE venta (id TEXT PRIMARY KEY, fecha_hora TEXT NOT NULL, estado TEXT NOT NULL DEFAULT 'activa', updated_at TEXT NOT NULL)");
    await viejo.execute('CREATE TABLE linea_venta (id TEXT PRIMARY KEY, venta_id TEXT NOT NULL, precio_aplicado REAL NOT NULL, cantidad INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL)');
    await ponerAlDiaEsquemaDeLibro(viejo);
    await ponerAlDiaEsquemaDeLibro(viejo);
    final tablas = (await viejo.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
    expect(tablas, contains('compra_insumo'));
    // Y calificado, como cuando el libro está adjunto bajo un alias.
    await db.execute("ATTACH DATABASE '${p.join(dir.path, 'libro-viejo.db')}' AS viejo");
    await viejo.close();
    await db.execute('DROP TABLE viejo.compra_insumo');
    await ponerAlDiaEsquemaDeLibro(db, alias: 'viejo');
    expect((await db.rawQuery("SELECT name FROM viejo.sqlite_master WHERE type='table' AND name='compra_insumo'")), hasLength(1));
    await db.execute('DETACH DATABASE viejo');
  });

  test('el ejemplo del dueño: dos de 5 kg a 2.000 y una de 2,5 kg a 1.000 → 0,40 por gramo', () async {
    final hoy = DateTime.now();
    final notifier = container.read(compraInsumoNotifierProvider.notifier);
    await notifier.anotar(compra('c1', hoy.subtract(const Duration(days: 3)), presentaciones: 2, contenido: 5000, pagado: 4000));
    await notifier.anotar(compra('c2', hoy.subtract(const Duration(days: 1)), contenido: 2500, pagado: 1000));

    final costo = (await container.read(costoDeInsumosProvider.future))['harina']!;
    expect(costo.costoPorUnidadBase, closeTo(5000 / 12500, 1e-9)); // 0,40 y no el último (0,40) ni el arranque (0,90)
    expect(costo.origen, OrigenDelCosto.promedio);

    // Una compra cara reciente mueve el promedio, no lo reemplaza.
    await notifier.anotar(compra('c3', hoy, contenido: 1000, pagado: 1000)); // 1,00/g
    final despues = (await container.read(costoDeInsumosProvider.future))['harina']!;
    expect(despues.costoPorUnidadBase, closeTo(6000 / 13500, 1e-9));
  });

  test('sin compras recientes se usa la última; sin ninguna, el arranque — y se dice cuál', () async {
    expect((await container.read(costoDeInsumosProvider.future))['harina']!.origen, OrigenDelCosto.arranque);
    expect((await container.read(costoDeInsumosProvider.future))['harina']!.costoPorUnidadBase, closeTo(0.9, 1e-9));

    await container.read(compraInsumoNotifierProvider.notifier).anotar(
      compra('vieja', DateTime.now().subtract(const Duration(days: 200)), contenido: 1000, pagado: 700),
    );
    final costo = (await container.read(costoDeInsumosProvider.future))['harina']!;
    expect(costo.origen, OrigenDelCosto.ultimaCompra);
    expect(costo.costoPorUnidadBase, closeTo(0.7, 1e-9));
  });

  test('anular una compra la saca del promedio sin borrarla del libro', () async {
    final hoy = DateTime.now();
    final notifier = container.read(compraInsumoNotifierProvider.notifier);
    await notifier.anotar(compra('c1', hoy, contenido: 1000, pagado: 1000));
    await notifier.anotar(compra('mal', hoy, contenido: 1000, pagado: 9000)); // se tecleó mal
    await notifier.anular('mal');

    expect((await container.read(costoDeInsumosProvider.future))['harina']!.costoPorUnidadBase, closeTo(1.0, 1e-9));
    expect(await db.query('compra_insumo'), hasLength(2), reason: 'marcada, no borrada');
  });

  test('las compras y sus totales cruzan libros, y el trimestre es la base del simplificado', () async {
    final notifier = container.read(compraInsumoNotifierProvider.notifier);
    await notifier.anotar(compra('a', DateTime(2026, 2, 10), contenido: 1000, pagado: 1000));
    final abierto = (await libros.libroAbierto(db))!;
    await db.update('libro_ventas', {'dias_con_ventas': diasPorLibro}, where: 'id = ?', whereArgs: [abierto.id]);
    await notifier.anotar(compra('b', DateTime(2026, 3, 5), contenido: 1000, pagado: 2000)); // abre otro libro

    expect((await libros.todos(db)).map((l) => l.cerrado), containsAll([true, false]));
    final trimestre = await container.read(totalComprasProvider((DateTime(2026, 1), DateTime(2026, 4))).future);
    expect(trimestre, 3000);
    final marzo = await container.read(comprasDeInsumosProvider((DateTime(2026, 3), DateTime(2026, 4))).future);
    expect(marzo.map((x) => x.id), ['b']);
  });

  test('el costeo toma el costo de las compras, no el del maestro', () async {
    await container.read(productoNotifierProvider.notifier).crear(
      Producto(id: 'pan', nombre: 'Pan', precioBase: 500, updatedAt: DateTime(2026)),
    );
    final articulos = container.read(articuloCosteoProvider.notifier);
    final registro = await articulos.asegurar('pan', '');
    await articulos.ponerLinea(registro.id, 'harina', 100); // 100 g
    await container.read(configCosteoProvider.notifier).guardar(ConfigCosteoRegistro(config: const c.ConfigCosteo(mermaPorDefecto: 0), updatedAt: DateTime.now()));

    // Sin compras: 100 g × 0,90 (arranque) = 90.
    expect((await container.read(costeoProvider.future)).calculadoDe('pan#')!.costoInsumosUnidad, closeTo(90, 1e-9));

    await container.read(compraInsumoNotifierProvider.notifier).anotar(
      compra('c', DateTime.now(), presentaciones: 2, contenido: 5000, pagado: 4000),
    );
    // Con compra: 100 g × 0,40 = 40.
    expect((await container.read(costeoProvider.future)).calculadoDe('pan#')!.costoInsumosUnidad, closeTo(40, 1e-9));
  });
}
