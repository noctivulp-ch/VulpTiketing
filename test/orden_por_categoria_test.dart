import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/configuracion/preferencias_notifier.dart';
import 'package:vulp_tiketing/features/producto/categoria_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_notifier.dart';
import 'package:vulp_tiketing/features/producto/producto_query_provider.dart';

/// El ajuste "ordenar por categoría" ordenaba por **categoria_id**, o sea por
/// UUID: el resultado era un orden arbitrario, distinto en cada aparato, que no
/// se parecía a nada de lo que el ajuste promete. Y sin títulos, ni siquiera se
/// veía dónde empezaba cada grupo.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vulp-orden');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);

    // Los ids van al revés que los nombres a propósito: si el orden saliera del
    // id, "Zanahorias" iría primero y la prueba lo cazaría.
    await db.insert('categoria', {
      'id': 'a-id',
      'nombre': 'Zanahorias',
      'updated_at': DateTime(2026).toIso8601String(),
    });
    await db.insert('categoria', {
      'id': 'z-id',
      'nombre': 'Bebidas',
      'updated_at': DateTime(2026).toIso8601String(),
    });

    Future<void> producto(String id, String nombre, String? categoria) => db.insert('producto', {
      'id': id,
      'nombre': nombre,
      'categoria_id': categoria,
      'precio_base': 1000.0,
      'updated_at': DateTime(2026).toIso8601String(),
    });

    await producto('p1', 'Fresco de cas', 'z-id');
    await producto('p2', 'Zanahoria rallada', 'a-id');
    await producto('p3', 'Agua', 'z-id');
    await producto('p4', 'Servilletas', null);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> contenedor(OrdenProducto orden) async {
    final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
    addTearDown(c.dispose);
    await c.read(preferenciasNotifierProvider.notifier).cambiarOrden(orden);
    // Las cargas van en cadena: base → productos → categorías.
    await c.read(preferenciasNotifierProvider.future);
    await c.read(productoNotifierProvider.future);
    await c.read(categoriaNotifierProvider.future);
    return c;
  }

  test('ordena por NOMBRE de categoría, no por su id', () async {
    final c = await contenedor(OrdenProducto.categoria);
    final lista = c.read(productoQueryProvider).requireValue;

    expect(
      lista.map((p) => p.nombre).toList(),
      // Bebidas antes que Zanahorias, y dentro de cada una, alfabético.
      ['Agua', 'Fresco de cas', 'Zanahoria rallada', 'Servilletas'],
    );
  });

  test('los productos sin categoría van al final', () async {
    final c = await contenedor(OrdenProducto.categoria);
    expect(c.read(productoQueryProvider).requireValue.last.nombre, 'Servilletas');
  });

  test('la lista se agrupa con un título por categoría', () async {
    final c = await contenedor(OrdenProducto.categoria);
    final grupos = c.read(productoAgrupadoProvider).requireValue;

    expect(grupos.map((g) => g.titulo).toList(), ['Bebidas', 'Zanahorias', sinCategoria]);
    expect(grupos.first.productos.map((p) => p.nombre), ['Agua', 'Fresco de cas']);
  });

  test('con otro orden hay un solo grupo, sin título', () async {
    // Un encabezado sobra cuando el orden se lee del propio contenido.
    final c = await contenedor(OrdenProducto.alfabetico);
    final grupos = c.read(productoAgrupadoProvider).requireValue;

    expect(grupos, hasLength(1));
    expect(grupos.single.titulo, isNull);
    expect(grupos.single.productos.map((p) => p.nombre), [
      'Agua',
      'Fresco de cas',
      'Servilletas',
      'Zanahoria rallada',
    ]);
  });
}
