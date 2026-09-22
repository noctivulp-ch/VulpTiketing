import 'dart:io';

import 'package:costeo/costeo.dart' as c;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/costeo/aplicar_precio.dart';
import 'package:vulp_tiketing/features/costeo/costeo_notifiers.dart';
import 'package:vulp_tiketing/features/costeo/costeo_provider.dart';
import 'package:vulp_tiketing/features/costeo/costo_fijo_model.dart';
import 'package:vulp_tiketing/features/costeo/insumo_model.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/producto/variante_model.dart';
import 'package:vulp_tiketing/features/sync/sync_server.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// El costeo cableado a la app (0040): las tablas nuevas, el volumen que
/// sale de las VENTAS REALES, el cálculo sobre el catálogo con variantes, y
/// la única puerta de escritura al catálogo — "aplicar precio", explícita.
///
/// Lo que no puede pasar y acá se vigila: que el costeo cambie un precio de
/// la carta sin que alguien lo haya pedido para ese artículo.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;
  late LibroVentasService libros;
  late ProviderContainer container;

  final cafe = Producto(
    id: 'cafe',
    nombre: 'Café',
    precioBase: 800,
    variantes: const [
      Variante(id: 'p', nombre: 'Pequeño', precio: 800, porDefecto: true),
      Variante(id: 'g', nombre: 'Grande', precio: 1200),
    ],
    updatedAt: DateTime(2026),
  );
  final casado = Producto(id: 'casado', nombre: 'Casado', precioBase: 3000, updatedAt: DateTime(2026));

  Future<void> vender(String id, DateTime cuando, String productoId, {String? variante, int cantidad = 1}) async {
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
      'producto_id': productoId,
      'variante': variante,
      'precio_aplicado': 1,
      'cantidad': cantidad,
      'updated_at': cuando.toIso8601String(),
    });
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-costeo');
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
    await container.read(productoNotifierProvider.notifier).crear(cafe);
    await container.read(productoNotifierProvider.notifier).crear(casado);
  });

  tearDown(() async {
    container.dispose();
    await libros.desadjuntar(db);
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('las cinco tablas están en el esquema nuevo, en la migración v7 y en el sync', () async {
    final tablas = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
    expect(tablas, containsAll(['insumo', 'costo_fijo', 'config_costeo', 'articulo_costeo', 'linea_receta']));
    expect(tablasSincronizables, containsAll(['insumo', 'costo_fijo', 'config_costeo', 'articulo_costeo', 'linea_receta']));

    // Una base v6 (sin las tablas) sube a v7 sin tocar lo que tenía.
    final v6 = await databaseFactory.openDatabase(p.join(dir.path, 'v6.db'), options: OpenDatabaseOptions(singleInstance: false));
    await v6.execute('CREATE TABLE producto (id TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio_base REAL NOT NULL, variantes TEXT, updated_at TEXT NOT NULL)');
    await v6.insert('producto', {'id': 'x', 'nombre': 'X', 'precio_base': 1, 'updated_at': DateTime(2026).toIso8601String()});
    await AppDatabase.crearTablasDeCosteo(v6);
    await AppDatabase.crearTablasDeCosteo(v6); // dos veces no rompe
    expect(await v6.query('producto'), hasLength(1));
    expect(await v6.query('insumo'), isEmpty);
    await v6.close();
  });

  test('sin costear nada, el catálogo entero aparece con sus alertas y ningún precio cambia', () async {
    final costeo = await container.read(costeoProvider.future);
    // Café pequeño, Café grande, Casado: una fila por lo que se vende como unidad.
    expect(costeo.resultado.articulos.map((a) => a.articulo.nombre), ['Café · Pequeño', 'Café · Grande', 'Casado']);
    for (final a in costeo.resultado.articulos) {
      expect(a.alertas, containsAll([c.Alerta.sinReceta, c.Alerta.sinVolumen]));
    }
    final productos = await container.read(productoNotifierProvider.future);
    expect(productos.firstWhere((x) => x.id == 'casado').precioBase, 3000, reason: 'informa, no toca');
  });

  test('el volumen sale de las ventas de los últimos 30 días, por variante, y lo viejo sin variante va a la por defecto', () async {
    final hoy = DateTime.now();
    await vender('v1', hoy.subtract(const Duration(days: 2)), 'cafe', variante: 'Grande', cantidad: 3);
    await vender('v2', hoy.subtract(const Duration(days: 5)), 'cafe', cantidad: 2); // antes de las variantes
    await vender('v3', hoy.subtract(const Duration(days: 10)), 'casado', cantidad: 7);
    await vender('v4', hoy.subtract(const Duration(days: 45)), 'casado', cantidad: 100); // fuera de la ventana

    final volumen = await container.read(volumenRealProvider.future);
    expect(volumen['cafe#g'], 3);
    expect(volumen['cafe#p'], 2, reason: 'la venta sin variante se atribuye a la por defecto');
    expect(volumen['casado#'], 7);

    final costeo = await container.read(costeoProvider.future);
    final casadoC = costeo.calculadoDe('casado#')!;
    expect(casadoC.articulo.unidadesMes, 7);
    expect(casadoC.articulo.volumenEsReal, isTrue);
    expect(casadoC.alertas, isNot(contains(c.Alerta.volumenEstimado)));
  });

  test('sin ventas manda la estimación, y se avisa que es estimada', () async {
    final articulos = container.read(articuloCosteoProvider.notifier);
    final registro = await articulos.asegurar('casado', '');
    await articulos.guardarArticulo(registro.copyWith(unidadesEstimadasMes: 50, updatedAt: DateTime.now()));

    final costeo = await container.read(costeoProvider.future);
    final casadoC = costeo.calculadoDe('casado#')!;
    expect(casadoC.articulo.unidadesMes, 50);
    expect(casadoC.alertas, contains(c.Alerta.volumenEstimado));
  });

  test('receta, insumos, costos fijos y parámetros llegan al cálculo', () async {
    await container.read(insumoNotifierProvider.notifier).crear(
      InsumoRegistro(
        id: 'arroz', nombre: 'Arroz', unidadBase: c.UnidadBase.gramo,
        contenidoPorCompra: 1000, precioCompra: 1200, updatedAt: DateTime.now(),
      ),
    );
    await container.read(costoFijoNotifierProvider.notifier).crear(
      CostoFijoRegistro(id: 'alq', concepto: 'Alquiler', montoMensual: 100000, updatedAt: DateTime.now()),
    );
    await container.read(configCosteoProvider.notifier).guardar(const c.ConfigCosteo(margenObjetivo: 0.5, comisionMediosPago: 0, mermaPorDefecto: 0, redondeoPrecio: 1));
    final articulos = container.read(articuloCosteoProvider.notifier);
    final registro = await articulos.asegurar('casado', '');
    await articulos.guardarArticulo(registro.copyWith(unidadesEstimadasMes: 100, updatedAt: DateTime.now()));
    await articulos.ponerLinea(registro.id, 'arroz', 200); // 200 g de arroz por casado

    final costeo = await container.read(costeoProvider.future);
    final casadoC = costeo.calculadoDe('casado#')!;
    expect(casadoC.costoInsumosUnidad, closeTo(240, 1e-9)); // 200 g × 1,2
    expect(casadoC.overheadUnidad, closeTo(1000, 1e-9)); // 100.000 / 100
    expect(casadoC.costoTotalUnidad, closeTo(1240, 1e-9));
    expect(casadoC.precioSugerido, closeTo(2480, 1e-9)); // / (1 − 0,5)
    // Se cobra 3.000: margen real = (3000 − 1240) / 3000 = 58,7 % ≥ 50 %.
    expect(casadoC.margenReal, closeTo((3000 - 1240) / 3000, 1e-9));
    expect(casadoC.alertas, isNot(contains(c.Alerta.margenBajoObjetivo)));

    // Quitar la línea deja al artículo sin receta otra vez.
    final linea = (await container.read(articuloCosteoProvider.future)).lineasDe(registro.id).single;
    await articulos.quitarLinea(linea.id);
    final despues = await container.read(costeoProvider.future);
    expect(despues.calculadoDe('casado#')!.alertas, contains(c.Alerta.sinReceta));
  });

  test('la configuración se guarda una sola vez y vuelve a leerse', () async {
    expect((await container.read(configCosteoProvider.future)).margenObjetivo, 0.6, reason: 'de fábrica');
    await container.read(configCosteoProvider.notifier).guardar(const c.ConfigCosteo(margenObjetivo: 0.45, metodoReparto: c.MetodoReparto.tiempo));
    await container.read(configCosteoProvider.notifier).guardar(const c.ConfigCosteo(margenObjetivo: 0.4));
    expect(await db.query('config_costeo'), hasLength(1));
    container.invalidate(configCosteoProvider);
    expect((await container.read(configCosteoProvider.future)).margenObjetivo, 0.4);
  });

  test('aplicar precio escribe SOLO el artículo pedido: base, o variante (y base si es la por defecto)', () async {
    final costeo = await container.read(costeoProvider.future);
    final aplicar = container.read(aplicarPrecioProvider);

    await aplicar(costeo.articulos['casado#']!, 3500);
    await aplicar(costeo.articulos['cafe#g']!, 1500);

    var productos = await container.read(productoNotifierProvider.future);
    var cafeGuardado = productos.firstWhere((x) => x.id == 'cafe');
    expect(productos.firstWhere((x) => x.id == 'casado').precioBase, 3500);
    expect(cafeGuardado.variantes.firstWhere((v) => v.id == 'g').precio, 1500);
    expect(cafeGuardado.precioBase, 800, reason: 'Grande no es la por defecto: el base no se toca');
    expect(cafeGuardado.variantePorDefecto!.id, 'p');

    await aplicar(costeo.articulos['cafe#p']!, 900);
    productos = await container.read(productoNotifierProvider.future);
    cafeGuardado = productos.firstWhere((x) => x.id == 'cafe');
    expect(cafeGuardado.precioBase, 900, reason: 'Pequeño es la por defecto: van en sincronía');
    expect(cafeGuardado.variantes.map((v) => v.precio), [900, 1500]);
  });
}
