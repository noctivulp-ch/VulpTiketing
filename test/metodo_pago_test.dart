import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/linea_venta_model.dart';
import 'package:vulp_tiketing/features/venta/venta_dao.dart';
import 'package:vulp_tiketing/features/venta/venta_model.dart';
import 'package:vulp_tiketing/features/venta/venta_notifier.dart';

/// Dos formas de cobrar: efectivo —la normal— y SINPE, con el identificador de
/// la transferencia opcional y anotado **después**.
///
/// Al cobrar hay cola y nadie transcribe doce dígitos con el cliente delante.
/// Lo que no puede perderse es *que* fue SINPE; el número se completa con calma.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-pago');
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
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> vender(
    String id,
    DateTime cuando, {
    MetodoPago metodo = MetodoPago.efectivo,
    double precio = 2500,
  }) async {
    await VentaDao(db).guardar(
      Venta(
        id: id,
        fechaHora: cuando,
        estado: EstadoVenta.activa,
        metodoPago: metodo,
        updatedAt: cuando,
      ),
      [
        LineaVenta(
          id: 'l-$id',
          ventaId: id,
          productoId: 'p1',
          precioAplicado: precio,
          cantidad: 1,
          updatedAt: cuando,
        ),
      ],
    );
  }

  test('efectivo es lo que pasa si nadie hace nada', () async {
    await vender('v1', DateTime(2026, 3, 4, 12));

    final leida = (await VentaDao(db).listar()).single;

    expect(leida.metodoPago, MetodoPago.efectivo);
    expect(leida.referenciaPago, isNull);
  });

  test('una venta marcada como SINPE se guarda así', () async {
    await vender('v1', DateTime(2026, 3, 4, 12), metodo: MetodoPago.sinpe);

    expect((await VentaDao(db).listar()).single.metodoPago, MetodoPago.sinpe);
  });

  group('la referencia se anota después', () {
    ProviderContainer contenedor() {
      final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
      addTearDown(c.dispose);
      return c;
    }

    test('se puede agregar a una venta ya cobrada', () async {
      await vender('v1', DateTime(2026, 3, 4, 12), metodo: MetodoPago.sinpe);
      final c = contenedor();

      await c
          .read(ventaNotifierProvider.notifier)
          .anotarReferenciaDePago('v1', '  2026030412345  ');

      // Recortada: se copia y se pega desde la app del banco, con espacios.
      expect((await VentaDao(db).listar()).single.referenciaPago, '2026030412345');
    });

    test('vacío la borra: alguien anota mal y tiene que poder deshacerlo', () async {
      await vender('v1', DateTime(2026, 3, 4, 12), metodo: MetodoPago.sinpe);
      final c = contenedor();
      await c.read(ventaNotifierProvider.notifier).anotarReferenciaDePago('v1', '123');

      await c.read(ventaNotifierProvider.notifier).anotarReferenciaDePago('v1', '   ');

      // `null` y no cadena vacía: "sin referencia" es la ausencia del dato.
      expect((await VentaDao(db).listar()).single.referenciaPago, isNull);
    });

    test('no toca nada más de la venta', () async {
      // La decisión 0009 dice que una venta no se edita. Esta excepción es
      // acotada a propósito: si además cambiara importes o estado, sería
      // exactamente lo que 0009 prohíbe.
      final cuando = DateTime(2026, 3, 4, 12);
      await vender('v1', cuando, metodo: MetodoPago.sinpe, precio: 3800);
      final antes = (await VentaDao(db).listar()).single;
      final c = contenedor();

      await c.read(ventaNotifierProvider.notifier).anotarReferenciaDePago('v1', '999');
      final despues = (await VentaDao(db).listar()).single;

      expect(despues.estado, antes.estado);
      expect(despues.fechaHora, antes.fechaHora);
      expect(despues.metodoPago, antes.metodoPago);
      expect(despues.motivoReversion, antes.motivoReversion);
      // El `updated_at` SÍ cambia: es lo que hace que la anotación gane en la
      // sincronización (LWW, decisión 0005).
      expect(despues.updatedAt.isAfter(antes.updatedAt), isTrue);
    });
  });

  test('el reporte dice cuánto entró por SINPE', () async {
    final dia = DateTime(2026, 3, 4);
    await vender('v1', dia.add(const Duration(hours: 9)), precio: 1000);
    await vender('v2', dia.add(const Duration(hours: 13)), metodo: MetodoPago.sinpe, precio: 2500);
    await vender('v3', dia.add(const Duration(hours: 14)), metodo: MetodoPago.sinpe, precio: 500);

    final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
    addTearDown(c.dispose);
    final reporte = await c.read(
      reportesProvider(ReportesParametros(rango: RangoReporte.dia, fechaReferencia: dia)).future,
    );

    expect(reporte.total, closeTo(4000, 0.001));
    expect(reporte.porSinpe, closeTo(3000, 0.001));
    // El efectivo es la resta: mientras haya dos formas de cobrar, un solo
    // número contesta la pregunta entera.
    expect(reporte.porEfectivo, closeTo(1000, 0.001));
  });

  test('una venta revertida no cuenta como SINPE', () async {
    final dia = DateTime(2026, 3, 4);
    await vender('v1', dia.add(const Duration(hours: 9)), metodo: MetodoPago.sinpe, precio: 2000);
    await db.update('venta', {'estado': 'revertida'}, where: 'id = ?', whereArgs: ['v1']);

    final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
    addTearDown(c.dispose);
    final reporte = await c.read(
      reportesProvider(ReportesParametros(rango: RangoReporte.dia, fechaReferencia: dia)).future,
    );

    expect(reporte.porSinpe, 0, reason: 'los reportes excluyen las revertidas, también acá');
  });

  test('un libro escrito ANTES de las columnas se pone al día solo', () async {
    // El caso real: un aparato con la app vieja, o un backup de antes. Un libro
    // es un archivo suelto, así que su esquema se actualiza al adjuntarlo.
    final viejo = await databaseFactory.openDatabase(
      p.join(dir.path, 'libro-viejo.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await viejo.execute('''
      CREATE TABLE venta (
        id TEXT PRIMARY KEY, fecha_hora TEXT NOT NULL, detalle TEXT,
        estado TEXT NOT NULL DEFAULT 'activa', motivo_reversion TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await viejo.insert('venta', {
      'id': 'antigua',
      'fecha_hora': DateTime(2025, 5, 5).toIso8601String(),
      'estado': 'activa',
      'updated_at': DateTime(2025, 5, 5).toIso8601String(),
    });

    await ponerAlDiaEsquemaDeLibro(viejo);

    final columnas = {
      for (final c in await viejo.rawQuery('PRAGMA table_info(venta)')) c['name'] as String,
    };
    expect(columnas, containsAll(['metodo_pago', 'referencia_pago']));
    // Y la fila que ya estaba queda en efectivo, que es lo que era.
    final fila = (await viejo.query('venta')).single;
    expect(Venta.fromMap(fila).metodoPago, MetodoPago.efectivo);
    await viejo.close();
  });

  test('ponerlo al día dos veces no rompe nada', () async {
    // Se llama en cada ATTACH, así que tiene que ser inocuo repetido.
    await ponerAlDiaEsquemaDeLibro(db);
    await ponerAlDiaEsquemaDeLibro(db);

    final columnas = {
      for (final c in await db.rawQuery('PRAGMA table_info(venta)')) c['name'] as String,
    };
    expect(columnas.where((c) => c == 'metodo_pago'), hasLength(1));
  });

  test('anotar no recarga el libro entero', () async {
    // Escribir UNA columna no puede costar traerse todas las ventas a memoria.
    // Con el volumen medido son 117 k, y nadie observa esa lista: las pantallas
    // consultan por `reportesProvider` y `detalleRangoProvider`.
    for (var i = 0; i < 40; i++) {
      await vender('v$i', DateTime(2026, 3, 4, 8 + (i % 12)), metodo: MetodoPago.sinpe);
    }
    final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
    addTearDown(c.dispose);
    // Se observa a propósito, para poder ver en qué estado queda.
    final sub = c.listen(ventaNotifierProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(ventaNotifierProvider.future);

    await c.read(ventaNotifierProvider.notifier).anotarReferenciaDePago('v3', '123');

    // Queda invalidado, no recargado: si se hubiera recargado, el estado ya
    // tendría datos frescos sin pasar por `loading`.
    expect(c.read(ventaNotifierProvider).isLoading, isTrue);
    // Y al pedirlo de verdad, trae lo escrito.
    final ventas = await c.read(ventaNotifierProvider.future);
    expect(ventas.firstWhere((v) => v.id == 'v3').referenciaPago, '123');
  });
}
