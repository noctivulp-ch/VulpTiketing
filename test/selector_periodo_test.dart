import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/core/theme/bento_bandeja.dart';
import 'package:vulp_tiketing/core/theme/bento_theme.dart';
import 'package:vulp_tiketing/features/reportes/periodos_con_datos_provider.dart';
import 'package:vulp_tiketing/features/reportes/ui/calendario_periodo.dart';
import 'package:vulp_tiketing/features/venta/libro_ventas.dart';

/// Elegir un período era a ciegas: se tocaba un día, se esperaba la carga y
/// aparecía "sin ventas". Y para la semana, `showDatePicker` pedía "elegí un
/// día de la semana", que es una pregunta que nadie se hace.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;
  late Database db;

  // Miércoles 4 y jueves 5 de marzo de 2026. La semana del 2 al 8.
  final conVenta = [DateTime(2026, 3, 4, 12), DateTime(2026, 3, 5, 12)];

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vulp-periodo');
    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'vulp_tiketing.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.crearEsquema(db);
    await aplicarEsquemaLibro(db);

    for (final (i, cuando) in conVenta.indexed) {
      await db.insert('venta', {
        'id': 'v$i',
        'fecha_hora': cuando.toIso8601String(),
        'estado': 'activa',
        'updated_at': cuando.toIso8601String(),
      });
    }
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('los períodos con datos', () {
    test('un día con ventas se distingue de uno sin ellas', () async {
      final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
      addTearDown(c.dispose);

      final datos = await c.read(periodosConDatosProvider(2026).future);

      expect(datos.tieneDia(DateTime(2026, 3, 4)), isTrue);
      expect(datos.tieneDia(DateTime(2026, 3, 6)), isFalse);
    });

    test('la semana cuenta si CUALQUIER día suyo tiene ventas', () async {
      final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
      addTearDown(c.dispose);
      final datos = await c.read(periodosConDatosProvider(2026).future);

      // El lunes 2 no tiene ventas, pero su semana sí.
      expect(datos.tieneSemana(DateTime(2026, 3, 2)), isTrue);
      // La semana siguiente no tiene ninguna.
      expect(datos.tieneSemana(DateTime(2026, 3, 9)), isFalse);
    });

    test('mes y año se derivan de los mismos días, sin otra consulta', () async {
      final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
      addTearDown(c.dispose);
      final datos = await c.read(periodosConDatosProvider(2026).future);

      expect(datos.tieneMes(2026, 3), isTrue);
      expect(datos.tieneMes(2026, 4), isFalse);
      expect(datos.tieneAnio(2026), isTrue);
    });

    test('una venta revertida no cuenta como día con datos', () async {
      // Si contara, el calendario mandaría a un día que el reporte muestra en
      // cero: los reportes excluyen las revertidas.
      await db.update('venta', {'estado': 'revertida'}, where: 'id = ?', whereArgs: ['v0']);
      final c = ProviderContainer(overrides: [databaseProvider.overrideWith((ref) async => db)]);
      addTearDown(c.dispose);

      final datos = await c.read(periodosConDatosProvider(2026).future);

      expect(datos.tieneDia(DateTime(2026, 3, 4)), isFalse);
      expect(datos.tieneDia(DateTime(2026, 3, 5)), isTrue);
    });
  });

  group('el calendario', () {
    Future<void> abrir(WidgetTester tester, {required bool porSemana}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWith((ref) async => db)],
          child: MaterialApp(
            theme: buildBentoTheme(AcentoTinte.oro),
            home: Scaffold(
              body: CalendarioPeriodo(
                actual: DateTime(2026, 3, 4),
                hoy: DateTime(2026, 3, 20),
                porSemana: porSemana,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }

    testWidgets('marca los días que tienen ventas', (tester) async {
      await abrir(tester, porSemana: false);

      // La marca es un punto dentro del pozo del día. Se cuentan los pozos con
      // punto, no los días: es lo que se ve.
      final marcas = find.byWidgetPredicate(
        (w) => w is DecoratedBox && (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(marcas, findsNWidgets(conVenta.length));
    });

    testWidgets('por semana resalta los siete días, no uno', (tester) async {
      await abrir(tester, porSemana: true);

      // La semana del 2 al 8 de marzo de 2026, entera.
      final seleccionados = tester
          .widgetList<BentoPozo>(find.byType(BentoPozo))
          .where((p) => p.seleccionado)
          .length;
      expect(seleccionados, 7, reason: 'la semana se elige como un bloque, no día por día');
    });

    testWidgets('por día resalta solo el día elegido', (tester) async {
      await abrir(tester, porSemana: false);

      final seleccionados = tester
          .widgetList<BentoPozo>(find.byType(BentoPozo))
          .where((p) => p.seleccionado)
          .length;
      expect(seleccionados, 1);
    });

    testWidgets('los días que todavía no llegaron no se pueden tocar', (tester) async {
      await abrir(tester, porSemana: false);

      // Hoy es el 20; del 21 en adelante no hay nada que mirar.
      final pozos = tester.widgetList<BentoPozo>(find.byType(BentoPozo)).toList();
      expect(pozos.where((p) => p.onTap == null), hasLength(31 - 20));
    });
  });
}
