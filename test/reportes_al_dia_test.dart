import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/auth/sesion_notifier.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/reportes/ui/reportes_screen.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';
import 'package:vulp_tiketing/features/venta/venta_en_curso_notifier.dart';

/// Una venta cobrada tiene que verse en Reportes **sin cerrar la app**.
///
/// El usuario lo encontró en el aparato: cobraba, entraba a Reportes y el total
/// del día seguía como estaba al arrancar. En una caja eso es un número
/// equivocado a la vista, no una molestia de refresco.
///
/// La causa: `reportesProvider` lee la base por su cuenta y no observa al libro
/// de ventas, así que nada lo invalidaba. Se ataca por los dos lados — al
/// guardar (la causa inmediata) y al abrir la pantalla (que además cubre lo que
/// cambió por sincronización, por una reversión, o porque pasó la medianoche).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vulp-reportes-dia');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await aplicarEsquemaLibro(db);
    await db.insert('categoria', {
      'id': 'cat',
      'nombre': 'Arroces',
      'updated_at': DateTime(2026).toIso8601String(),
    });
    await db.insert('producto', {
      'id': 'p0',
      'nombre': 'Casado',
      'categoria_id': 'cat',
      'precio_base': 3000.0,
      'updated_at': DateTime(2026).toIso8601String(),
    });
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ProviderContainer contenedor() {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => db),
        libroVentasServiceProvider.overrideWith(
          (ref) async => LibroVentasService(directorio: dir.path),
        ),
        sesionNotifierProvider.overrideWith(() => _SesionFija(Rol.gerente)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  ReportesParametros hoy() => ReportesParametros(rango: RangoReporte.dia, fechaReferencia: DateTime.now());

  test('cobrar una venta actualiza el total del día, sin reiniciar nada', () async {
    final c = contenedor();

    // Se LEE primero, que es lo que deja el resultado cacheado: sin esta
    // lectura previa el fallo no se reproduce, porque la primera consulta ya
    // saldría con la venta dentro.
    final antes = await c.read(reportesProvider(hoy()).future);
    expect(antes.total, 0);

    final carrito = c.read(ventaEnCursoNotifierProvider.notifier);
    carrito.agregarLineaDeCatalogo(productoId: 'p0', precioAplicado: 3000);
    await carrito.guardar();

    final despues = await c.read(reportesProvider(hoy()).future);
    expect(despues.total, 3000, reason: 'la venta recién cobrada no llegó al reporte');
  });

  test('dos ventas seguidas suman las dos', () async {
    // Que el arreglo no se quede en "refresca una vez".
    final c = contenedor();
    await c.read(reportesProvider(hoy()).future);

    for (var i = 0; i < 2; i++) {
      final carrito = c.read(ventaEnCursoNotifierProvider.notifier);
      carrito.agregarLineaDeCatalogo(productoId: 'p0', precioAplicado: 3000);
      await carrito.guardar();
      await c.read(reportesProvider(hoy()).future);
    }

    expect((await c.read(reportesProvider(hoy()).future)).total, 6000);
  });

  testWidgets('abrir la pantalla de Reportes refresca lo que muestra', (tester) async {
    // La otra mitad: una venta que entró por fuera —sincronización, una
    // reversión desde otro sitio— no pasa por `guardar()`, así que abrir la
    // pantalla tiene que traer lo que haya en la base.
    final c = contenedor();
    await tester.runAsync(() => c.read(reportesProvider(hoy()).future));

    // Se escribe DIRECTO en la base, saltándose el notifier a propósito.
    await tester.runAsync(() async {
      final f = DateTime.now().toIso8601String();
      await db.insert('venta', {'id': 'v9', 'fecha_hora': f, 'estado': 'activa', 'updated_at': f});
      await db.insert('linea_venta', {
        'id': 'l9',
        'venta_id': 'v9',
        'producto_id': 'p0',
        'precio_aplicado': 4500.0,
        'cantidad': 1,
        'updated_at': f,
      });
    });

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: buildBentoTheme(AcentoTinte.oro), home: const ReportesScreen()),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(
      (await tester.runAsync(() => c.read(reportesProvider(hoy()).future)))!.total,
      4500,
      reason: 'la pantalla no refrescó al abrirse',
    );
    expect(tester.takeException(), isNull);
  });
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this.rol);

  final Rol rol;

  @override
  Rol? build() => rol;
}
