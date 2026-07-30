import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/producto/categoria_model.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_model.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/venta_notifier.dart';

/// Regresión: la PRIMERA operación después de restaurar un backup fallaba con
/// `DatabaseException(error database_closed)`.
///
/// Restaurar cierra la conexión (hay que reemplazar el archivo) e invalida
/// `databaseProvider`. Pero los Notifiers guardaban su DAO en un campo asignado
/// dentro de `build()`, y la reconstrucción de Riverpod es ASÍNCRONA: leer
/// `.notifier` devuelve la misma instancia de siempre, con su DAO todavía
/// apuntando a la conexión cerrada. La segunda llamada ya funcionaba, así que
/// en uso real se ve como "falló una vez y después anduvo" — el peor tipo de
/// fallo para diagnosticar.
///
/// Es el tercer bug de la misma familia en este proyecto (ver
/// docs/arquitectura/gestion-estado.md): un campo asignado en `build()` que se
/// lee cuando `build()` todavía no volvió a correr.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late String ruta;
  late Database conexionActual;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-reabrir');
    ruta = p.join(dir.path, 'vulp_tiketing.db');
    // Archivo real, no `:memory:`: cerrar una base en memoria destruye los
    // datos, y lo que se prueba es justamente reabrir la misma base.
    final inicial = await databaseFactory.openDatabase(
      ruta,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(inicial);
    await aplicarEsquemaLibro(inicial);
    await inicial.close();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Contenedor que abre una conexión NUEVA cada vez que se resuelve
  /// `databaseProvider`, igual que `AppDatabase.open()` tras un `close()`.
  ProviderContainer contenedor() {
    return ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async {
          conexionActual = await databaseFactory.openDatabase(
            ruta,
            options: OpenDatabaseOptions(singleInstance: false),
          );
          return conexionActual;
        }),
        libroVentasServiceProvider.overrideWith(
          (ref) async => LibroVentasService(directorio: dir.path),
        ),
      ],
    );
  }

  /// Reproduce lo que hace restaurar un `.tiketback`: cierra la conexión y
  /// manda a reabrir.
  Future<void> simularRestauracion(ProviderContainer container) async {
    await conexionActual.close();
    container.invalidate(databaseProvider);
  }

  test('ProductoNotifier: la primera escritura tras reabrir la base funciona', () async {
    final container = contenedor();
    addTearDown(container.dispose);
    await container.read(productoNotifierProvider.future);

    await simularRestauracion(container);

    await container.read(productoNotifierProvider.notifier).crear(Producto(
          id: 'p1',
          nombre: 'Café',
          precioBase: 800,
          updatedAt: DateTime(2026),
        ));

    final productos = await container.read(productoNotifierProvider.future);
    expect(productos.map((x) => x.nombre), contains('Café'));
  });

  test('CategoriaNotifier: la primera escritura tras reabrir la base funciona', () async {
    final container = contenedor();
    addTearDown(container.dispose);
    await container.read(categoriaNotifierProvider.future);

    await simularRestauracion(container);

    await container.read(categoriaNotifierProvider.notifier).crear(Categoria(
          id: 'c1',
          nombre: 'Bebidas',
          updatedAt: DateTime(2026),
        ));

    final categorias = await container.read(categoriaNotifierProvider.future);
    expect(categorias.map((x) => x.nombre), contains('Bebidas'));
  });

  test('VentaNotifier: la primera lectura tras reabrir la base funciona', () async {
    final container = contenedor();
    addTearDown(container.dispose);
    await container.read(ventaNotifierProvider.future);

    await simularRestauracion(container);

    expect(await container.read(ventaNotifierProvider.future), isEmpty);
  });

  test('varias escrituras seguidas tras reabrir siguen funcionando', () async {
    // El bug se "curaba solo" al segundo intento, así que una prueba que
    // escriba una sola vez podría pasar por casualidad si el orden cambia.
    final container = contenedor();
    addTearDown(container.dispose);
    await container.read(productoNotifierProvider.future);

    await simularRestauracion(container);

    for (var i = 0; i < 3; i++) {
      await container.read(productoNotifierProvider.notifier).crear(Producto(
            id: 'p$i',
            nombre: 'Producto $i',
            precioBase: 100.0 * i,
            updatedAt: DateTime(2026),
          ));
    }

    expect(await container.read(productoNotifierProvider.future), hasLength(3));
  });
}
