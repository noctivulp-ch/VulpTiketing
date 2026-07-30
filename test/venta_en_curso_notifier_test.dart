import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/venta/venta_en_curso_notifier.dart';

/// Regresion de un bug critico: solo se podia guardar UNA venta por sesion.
///
/// `ventaIdBorrador` era un inicializador de campo (`final String x =
/// _uuid.v4();`) y el codigo asumia que `ref.invalidateSelf()` lo regeneraba.
/// No lo hace: Riverpod reutiliza la misma instancia de Notifier entre
/// reconstrucciones, asi que el inicializador corre una sola vez en la vida del
/// provider. La segunda venta moria con `UNIQUE constraint failed: venta.id`.
///
/// En una app de punto de venta eso significa que la caja deja de funcionar
/// despues del primer cobro. Ninguna prueba lo veia porque ninguna hacia dos
/// ventas seguidas — el caso mas normal del negocio.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> abrirDb() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('''
      CREATE TABLE venta (
        id TEXT PRIMARY KEY, fecha_hora TEXT NOT NULL, detalle TEXT,
        estado TEXT NOT NULL, motivo_reversion TEXT, updated_at TEXT NOT NULL
      );''');
    await db.execute('''
      CREATE TABLE linea_venta (
        id TEXT PRIMARY KEY, venta_id TEXT NOT NULL, producto_id TEXT,
        nombre_libre TEXT, precio_aplicado REAL NOT NULL,
        cantidad INTEGER NOT NULL, nota TEXT, updated_at TEXT NOT NULL
      );''');
    return db;
  }

  test('se pueden guardar varias ventas seguidas, cada una con su propio id', () async {
    final db = await abrirDb();
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      final carrito = container.read(ventaEnCursoNotifierProvider.notifier);
      carrito.agregarLineaLibre(nombreLibre: 'venta $i', precio: 1000 + i * 100);
      ids.add(carrito.ventaIdBorrador);
      await carrito.guardar();
    }

    expect(ids.toSet().length, equals(3), reason: 'cada venta necesita un id propio: $ids');

    final filas = await db.query('venta');
    expect(filas.length, equals(3), reason: 'las 3 ventas tienen que estar persistidas');
    expect(
      filas.map((f) => f['id']).toSet(),
      equals(ids.toSet()),
      reason: 'los ids persistidos deben ser los del borrador de cada venta',
    );
  });

  test('el carrito queda vacio despues de guardar', () async {
    final db = await abrirDb();
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    final carrito = container.read(ventaEnCursoNotifierProvider.notifier);
    carrito.agregarLineaLibre(nombreLibre: 'algo', precio: 500);
    await carrito.guardar();

    expect(
      container.read(ventaEnCursoNotifierProvider).lineas,
      isEmpty,
      reason: 'arrastrar las lineas de la venta anterior las cobraria dos veces',
    );
  });
}
