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
import 'package:vulp_tiketing/features/reportes/ui/reportes_screen.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// En Reportes, dos dedos de lado recorren los rangos y hacia abajo abren el
/// selector del rango actual.
///
/// Lo que más importa acá es el ROL: la Registradora solo tiene Día y Semana, y
/// un gesto que la lleve a Mes la dejaría en una pantalla de la que su propio
/// selector no la puede sacar.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('vulp-gestos-reportes');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await aplicarEsquemaLibro(db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> montar(WidgetTester tester, Rol rol) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) async => db),
          libroVentasServiceProvider.overrideWith(
            (ref) async => LibroVentasService(directorio: dir.path),
          ),
          sesionNotifierProvider.overrideWith(() => _SesionFija(rol)),
        ],
        child: MaterialApp(theme: buildBentoTheme(AcentoTinte.oro), home: const ReportesScreen()),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> dosDedos(WidgetTester tester, {double dx = 0, double dy = 0}) async {
    final uno = await tester.startGesture(const Offset(150, 300));
    final dos = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 8; i++) {
      await uno.moveBy(Offset(dx / 8, dy / 8));
      await dos.moveBy(Offset(dx / 8, dy / 8));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await uno.up();
    await dos.up();
    // Cambiar de rango dispara una consulta nueva, y las consultas a SQLite no
    // avanzan con el reloj falso de `pump`: sin `runAsync` la pantalla se
    // quedaría en el indicador de carga y no habría título que comprobar.
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('el Gerente recorre los cuatro rangos', (tester) async {
    await montar(tester, Rol.gerente);
    expect(find.text('Hoy'), findsOneWidget);

    await dosDedos(tester, dx: -160);
    expect(find.text('Esta semana'), findsOneWidget);

    await dosDedos(tester, dx: -160);
    expect(find.text('Este mes'), findsOneWidget);

    await dosDedos(tester, dx: -160);
    expect(find.text('Este año'), findsOneWidget);
  });

  testWidgets('y vuelve hacia atrás', (tester) async {
    await montar(tester, Rol.gerente);
    await dosDedos(tester, dx: -160);
    expect(find.text('Esta semana'), findsOneWidget);

    await dosDedos(tester, dx: 160);
    expect(find.text('Hoy'), findsOneWidget);
  });

  testWidgets('en los extremos no da la vuelta', (tester) async {
    await montar(tester, Rol.gerente);
    // Ya está en Día, el primero.
    await dosDedos(tester, dx: 160);
    expect(find.text('Hoy'), findsOneWidget);
  });

  testWidgets('la Registradora no llega a Mes: no es suyo', (tester) async {
    await montar(tester, Rol.registradora);

    await dosDedos(tester, dx: -160);
    expect(find.text('Esta semana'), findsOneWidget);

    // Semana es su último rango. El gesto no puede llevarla más allá.
    await dosDedos(tester, dx: -160);
    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('Este mes'), findsNothing);
  });

  testWidgets('dos dedos hacia abajo abren el selector del rango', (tester) async {
    await montar(tester, Rol.gerente);

    await dosDedos(tester, dy: 160);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Elegí el día'), findsOneWidget);
  });

  testWidgets('el selector que se abre es el del rango ACTUAL', (tester) async {
    await montar(tester, Rol.gerente);
    await dosDedos(tester, dx: -160);
    await dosDedos(tester, dx: -160);
    expect(find.text('Este mes'), findsOneWidget);

    await dosDedos(tester, dy: 160);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Elegí el mes'), findsOneWidget);
  });

  testWidgets('la Registradora no abre selector: no elige fecha', (tester) async {
    // Su selector de fecha no existe en la pantalla (el botón es Gerente-only),
    // así que el gesto tampoco puede dárselo por la puerta de atrás.
    await montar(tester, Rol.registradora);

    await dosDedos(tester, dy: 160);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Elegí el día'), findsNothing);
  });
  testWidgets('dos dedos hacia arriba abren el menú de exportación', (tester) async {
    await montar(tester, Rol.gerente);

    await dosDedos(tester, dy: -160);
    await tester.pump(const Duration(milliseconds: 400));

    // El gesto reemplaza a un "mantener presionado" que no se descubre solo.
    expect(find.text('Exportar reporte'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Tabla (CSV)'), findsOneWidget);
  });
}

class _SesionFija extends SesionNotifier {
  _SesionFija(this.rol);
  final Rol rol;

  @override
  Rol? build() => rol;
}
