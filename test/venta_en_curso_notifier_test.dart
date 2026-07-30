import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
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
    // Desde v3 las ventas viven en un libro; acá se aplican sus tablas sobre la
    // misma base en memoria (decisión 0025). El índice de libros también hace
    // falta, porque `guardar()` consulta la rotación antes de escribir.
    await db.execute(AppDatabase.esquema[2]); // libro_ventas
    await aplicarEsquemaLibro(db);
    return db;
  }

  test('se pueden guardar varias ventas seguidas, cada una con su propio id', () async {
    final db = await abrirDb();
    addTearDown(db.close);

    final dir = Directory.systemTemp.createTempSync('vulp-carrito');
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        // Sin esto el servicio intentaría resolver la carpeta real con
        // path_provider, que no existe en una prueba unitaria.
        libroVentasServiceProvider.overrideWith(
          (ref) async => LibroVentasService(directorio: dir.path),
        ),
      ],
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

    final dir = Directory.systemTemp.createTempSync('vulp-carrito');
    addTearDown(() => dir.deleteSync(recursive: true));
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        // Sin esto el servicio intentaría resolver la carpeta real con
        // path_provider, que no existe en una prueba unitaria.
        libroVentasServiceProvider.overrideWith(
          (ref) async => LibroVentasService(directorio: dir.path),
        ),
      ],
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
