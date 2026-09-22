import 'dart:io';

import 'package:costeo/costeo.dart' as c;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/costeo/config_costeo_model.dart';
import 'package:vulp_tiketing/features/costeo/costeo_notifiers.dart';
import 'package:vulp_tiketing/features/costeo/costeo_provider.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Impuestos y comisiones (0042). Lo que se vigila:
/// - la migración v8 copia la comisión única a SINPE y no toca nada más;
/// - en simplificado el impuesto va sobre compras y el IVA del producto se
///   ignora; en general el IVA del producto (o el por defecto) va dentro del
///   precio;
/// - la comisión que usa el cálculo es la ponderada por cómo se cobró.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;
  late LibroVentasService libros;
  late ProviderContainer container;

  Future<void> vender(String id, DateTime cuando, String productoId, double monto, {String metodo = 'efectivo'}) async {
    await libros.prepararPara(db, cuando);
    await db.insert('venta', {'id': id, 'fecha_hora': cuando.toIso8601String(), 'estado': 'activa', 'metodo_pago': metodo, 'updated_at': cuando.toIso8601String()});
    await db.insert('linea_venta', {'id': 'l-$id', 'venta_id': id, 'producto_id': productoId, 'precio_aplicado': monto, 'cantidad': 1, 'updated_at': cuando.toIso8601String()});
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-impuestos');
    db = await databaseFactory.openDatabase(p.join(dir.path, 'vulp_tiketing.db'), options: OpenDatabaseOptions(singleInstance: false));
    await AppDatabase.crearEsquema(db);
    libros = LibroVentasService(directorio: dir.path);
    await libros.adjuntarAbierto(db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        libroVentasServiceProvider.overrideWith((ref) async => libros),
      ],
    );
    await container.read(productoNotifierProvider.notifier).crear(Producto(id: 'casado', nombre: 'Casado', precioBase: 3000, updatedAt: DateTime(2026)));
    await container.read(productoNotifierProvider.notifier).crear(Producto(id: 'arroz', nombre: 'Arroz en grano', precioBase: 1000, tasaIva: 0.01, updatedAt: DateTime(2026)));
  });

  tearDown(() async {
    container.dispose();
    await libros.desadjuntar(db);
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('v7 → v8: producto gana tasa_iva y la comisión única pasa a SINPE', () async {
    final v7 = await databaseFactory.openDatabase(p.join(dir.path, 'v7.db'), options: OpenDatabaseOptions(singleInstance: false));
    await v7.execute('CREATE TABLE producto (id TEXT PRIMARY KEY, nombre TEXT NOT NULL, precio_base REAL NOT NULL, variantes TEXT, updated_at TEXT NOT NULL)');
    await v7.execute("CREATE TABLE config_costeo (id TEXT PRIMARY KEY, dias_abiertos_mes INTEGER NOT NULL DEFAULT 26, margen_objetivo REAL NOT NULL DEFAULT 0.6, comision_medios_pago REAL NOT NULL DEFAULT 0.03, merma_por_defecto REAL NOT NULL DEFAULT 0.05, tarifa_mano_obra_hora REAL NOT NULL DEFAULT 0, redondeo_precio REAL NOT NULL DEFAULT 50, metodo_reparto TEXT NOT NULL DEFAULT 'unidad', updated_at TEXT NOT NULL)");
    await v7.insert('config_costeo', {'id': 'unica', 'comision_medios_pago': 0.025, 'updated_at': DateTime(2026).toIso8601String()});

    await AppDatabase.agregarImpuestos(v7);
    await AppDatabase.agregarImpuestos(v7); // dos veces no rompe

    final cfg = ConfigCosteoRegistro.fromMap((await v7.query('config_costeo')).single);
    expect(cfg.comisionSinpe, closeTo(0.025, 1e-9), reason: 'la comisión de antes era la del banco');
    expect(cfg.comisionEfectivo, 0);
    expect(cfg.regimen, Regimen.simplificado);
    expect((await v7.rawQuery('PRAGMA table_info(producto)')).map((c) => c['name']), contains('tasa_iva'));
    await v7.close();
  });

  test('simplificado: el impuesto va sobre compras y el IVA del producto no cuenta', () async {
    await container.read(configCosteoProvider.notifier).guardar(
      ConfigCosteoRegistro(config: const c.ConfigCosteo(), factorIvaCompras: 0.03, factorRentaCompras: 0.025, updatedAt: DateTime.now()),
    );
    final costeo = await container.read(costeoProvider.future);
    expect(costeo.config.impuestoSobreCompras, closeTo(0.055, 1e-9));
    expect(costeo.calculadoDe('arroz#')!.articulo.tasaImpuesto, 0, reason: 'sin IVA en la venta');
    expect(costeo.resultado.impuestoSobrePrecioMes, 0);
  });

  test('general: cada producto lleva su IVA, o el por defecto, dentro del precio', () async {
    await container.read(configCosteoProvider.notifier).guardar(
      ConfigCosteoRegistro(config: const c.ConfigCosteo(), regimen: Regimen.general, tasaIvaPorDefecto: 0.13, updatedAt: DateTime.now()),
    );
    final costeo = await container.read(costeoProvider.future);
    expect(costeo.config.impuestoSobreCompras, 0);
    expect(costeo.calculadoDe('casado#')!.articulo.tasaImpuesto, 0.13, reason: 'el por defecto');
    expect(costeo.calculadoDe('arroz#')!.articulo.tasaImpuesto, 0.01, reason: 'el propio');
    expect(costeo.calculadoDe('casado#')!.impuestoPrecioUnidad, closeTo(3000 * 0.13 / 1.13, 1e-6));
  });

  test('la comisión efectiva es la ponderada por el mix real de pagos', () async {
    await container.read(configCosteoProvider.notifier).guardar(
      ConfigCosteoRegistro(config: const c.ConfigCosteo(), comisionEfectivo: 0, comisionSinpe: 0.02, updatedAt: DateTime.now()),
    );
    // Sin ventas: mix 0 → comisión 0.
    expect((await container.read(costeoProvider.future)).config.comisionMediosPago, 0);

    final hoy = DateTime.now();
    await vender('v1', hoy.subtract(const Duration(days: 1)), 'casado', 3000, metodo: 'sinpe');
    await vender('v2', hoy.subtract(const Duration(days: 2)), 'casado', 3000);
    await vender('v3', hoy.subtract(const Duration(days: 3)), 'casado', 3000);
    await vender('v4', hoy.subtract(const Duration(days: 4)), 'casado', 3000);
    container.invalidate(mixDePagoProvider);

    final costeo = await container.read(costeoProvider.future);
    expect(costeo.fraccionSinpe, closeTo(0.25, 1e-9));
    expect(costeo.config.comisionMediosPago, closeTo(0.02 * 0.25, 1e-9));
  });

  test('v8 → v9: tipo de negocio, y en servicios un artículo sin receta no avisa', () async {
    final v8 = await databaseFactory.openDatabase(p.join(dir.path, 'v8.db'), options: OpenDatabaseOptions(singleInstance: false));
    await v8.execute("CREATE TABLE config_costeo (id TEXT PRIMARY KEY, dias_abiertos_mes INTEGER NOT NULL DEFAULT 26, margen_objetivo REAL NOT NULL DEFAULT 0.6, comision_medios_pago REAL NOT NULL DEFAULT 0.03, merma_por_defecto REAL NOT NULL DEFAULT 0.05, tarifa_mano_obra_hora REAL NOT NULL DEFAULT 0, redondeo_precio REAL NOT NULL DEFAULT 50, metodo_reparto TEXT NOT NULL DEFAULT 'unidad', regimen TEXT NOT NULL DEFAULT 'simplificado', factor_iva_compras REAL NOT NULL DEFAULT 0.03, factor_renta_compras REAL NOT NULL DEFAULT 0.025, tasa_iva_por_defecto REAL NOT NULL DEFAULT 0.13, comision_efectivo REAL NOT NULL DEFAULT 0, comision_sinpe REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL)");
    await v8.insert('config_costeo', {'id': 'unica', 'updated_at': DateTime(2026).toIso8601String()});
    await AppDatabase.agregarTipoDeNegocio(v8);
    await AppDatabase.agregarTipoDeNegocio(v8);
    expect(ConfigCosteoRegistro.fromMap((await v8.query('config_costeo')).single).tipoNegocio, TipoNegocio.produccion);
    await v8.close();

    // Producción: el casado sin receta avisa. Servicios: no.
    expect((await container.read(costeoProvider.future)).calculadoDe('casado#')!.alertas, contains(c.Alerta.sinReceta));
    await container.read(configCosteoProvider.notifier).guardar(
      ConfigCosteoRegistro(config: const c.ConfigCosteo(), tipoNegocio: TipoNegocio.servicios, updatedAt: DateTime.now()),
    );
    final costeo = await container.read(costeoProvider.future);
    expect(costeo.config.recetasOpcionales, isTrue);
    expect(costeo.calculadoDe('casado#')!.alertas, isNot(contains(c.Alerta.sinReceta)));
  });
}
