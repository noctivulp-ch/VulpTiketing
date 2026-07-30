// Grupo A — acumulación de ventas.
//
// Correr con: flutter test test_estres/
//
// El nivel realista lleva presupuesto DURO (falla si no cumple). Los niveles
// alto y techo son caracterización: miden y registran, y solo fallan ante algo
// catastrófico o ante un resultado incorrecto. El volumen extremo es una
// dirección, no una meta.
@Timeout(Duration(minutes: 45))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';
import 'package:vulp_tiketing/features/venta/venta_dao.dart';
import 'package:vulp_tiketing/features/venta/venta_model.dart';
import 'package:vulp_tiketing/features/venta/linea_venta_model.dart';

import '_escalera.dart';
import '_generador.dart';

/// Acumula las mediciones para imprimir una tabla al final. Un montón de
/// líneas sueltas entre la salida del runner no se puede leer.
final _tabla = <List<String>>[];

void _anotar(String nivel, String medicion, String valor, String veredicto) {
  _tabla.add([nivel, medicion, valor, veredicto]);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDownAll(() {
    if (_tabla.isEmpty) return;
    final anchos = [0, 1, 2, 3]
        .map((c) => _tabla.map((f) => f[c].length).reduce((a, b) => a > b ? a : b))
        .toList();
    stdout.writeln('\n=== MEDICIONES — grupo A, acumulación de ventas ===');
    for (final fila in _tabla) {
      stdout.writeln('  ${fila[0].padRight(anchos[0])}  '
          '${fila[1].padRight(anchos[1])}  '
          '${fila[2].padLeft(anchos[2])}  ${fila[3]}');
    }
    stdout.writeln('\nPresupuestos objetivo en TABLET (se exige /$factorTablet al medir en laptop):');
    stdout.writeln('  guardar venta ${objetivoGuardarVenta.inMilliseconds} ms · '
        'reporte dia ${objetivoReporteDia.inMilliseconds} ms · '
        'reporte anio ${objetivoReporteAnio.inMilliseconds} ms');
  });

  for (final nivel in nivelesActivos) {
    group('nivel ${nivel.nombre}', () {
      late BaseDeEstres base;

      setUpAll(() async {
        base = await baseCon(nivel, log: stdout.writeln);
      });

      tearDownAll(() async {
        await base.db.close();
      });

      test('el volumen sembrado es el esperado', () async {
        final ventas = (await base.db.rawQuery('SELECT COUNT(*) c FROM venta')).first['c'] as int;
        final lineas = (await base.db.rawQuery('SELECT COUNT(*) c FROM linea_venta')).first['c'] as int;
        expect(ventas, equals(nivel.ventas));
        expect(lineas, equals(nivel.lineas));
        _anotar(nivel.nombre, 'filas totales', '${ventas + lineas}', '');
      });

      test('guardar una venta con la base cargada', () async {
        final dao = VentaDao(base.db);
        final fecha = DateTime(2026, 6, 15, 12, 30);
        // Se mide el camino real (VentaDao.guardar, transaccional), no un
        // insert suelto: es lo que hace el cajero.
        final (_, tomo) = await medir(() async {
          await dao.guardar(
            Venta(
              id: 'medicion-guardar',
              fechaHora: fecha,
              estado: EstadoVenta.activa,
              updatedAt: fecha,
            ),
            [
              LineaVenta(
                id: 'medicion-linea',
                ventaId: 'medicion-guardar',
                productoId: base.productoIds.first,
                precioAplicado: 900,
                cantidad: 1,
                updatedAt: fecha,
              ),
            ],
          );
        });

        final presupuesto = presupuestoLaptop(objetivoGuardarVenta);
        final cumple = tomo <= presupuesto;
        _anotar(nivel.nombre, 'guardar 1 venta', ms(tomo),
            cumple ? 'OK' : 'excede ${ms(presupuesto)}');

        if (nivel.trato == Trato.presupuestoDuro) {
          expect(tomo, lessThanOrEqualTo(presupuesto),
              reason: 'guardar una venta en ${nivel.nombre} tardó ${ms(tomo)}');
        } else {
          expect(tomo, lessThan(umbralCatastrofe));
        }
      });

      test('reporte del día', () async {
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWith((ref) async => base.db)],
        );
        addTearDown(container.dispose);

        final (reporte, tomo) = await medir(() => container.read(
              reportesProvider(ReportesParametros(
                rango: RangoReporte.dia,
                fechaReferencia: DateTime(2020, 6, 15),
              )).future,
            ));

        final presupuesto = presupuestoLaptop(objetivoReporteDia);
        _anotar(nivel.nombre, 'reporte dia', ms(tomo),
            tomo <= presupuesto ? 'OK' : 'excede ${ms(presupuesto)}');

        // Correctitud: los turnos tienen que sumar el total. Una medición de
        // rendimiento sobre un cálculo roto no vale nada.
        final sumaTurnos = reporte.porTurno.values.fold(0.0, (a, b) => a + b);
        expect(sumaTurnos, closeTo(reporte.total, 0.01),
            reason: 'los turnos deben sumar el total en ${nivel.nombre}');
        expect(reporte.total, greaterThan(0));

        if (nivel.trato == Trato.presupuestoDuro) {
          expect(tomo, lessThanOrEqualTo(presupuesto),
              reason: 'reporte del día en ${nivel.nombre} tardó ${ms(tomo)}');
        } else {
          expect(tomo, lessThan(umbralCatastrofe),
              reason: 'reporte del día en ${nivel.nombre} tardó ${ms(tomo)} — inservible');
        }
      });

      test('reporte del año', () async {
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWith((ref) async => base.db)],
        );
        addTearDown(container.dispose);

        final rssAntes = rssMb();
        final (reporte, tomo) = await medir(() => container.read(
              reportesProvider(ReportesParametros(
                rango: RangoReporte.anio,
                fechaReferencia: DateTime(2020, 6, 15),
              )).future,
            ));
        final rssDespues = rssMb();

        final presupuesto = presupuestoLaptop(objetivoReporteAnio);
        _anotar(nivel.nombre, 'reporte anio', ms(tomo),
            tomo <= presupuesto ? 'OK' : 'excede ${ms(presupuesto)}');
        _anotar(nivel.nombre, 'reporte anio RSS', '+${rssDespues - rssAntes} MB', '');

        final sumaTurnos = reporte.porTurno.values.fold(0.0, (a, b) => a + b);
        expect(sumaTurnos, closeTo(reporte.total, 0.01));

        if (nivel.trato == Trato.presupuestoDuro) {
          expect(tomo, lessThanOrEqualTo(presupuesto),
              reason: 'reporte del año en ${nivel.nombre} tardó ${ms(tomo)}');
        } else {
          expect(tomo, lessThan(umbralCatastrofe),
              reason: 'reporte del año en ${nivel.nombre} tardó ${ms(tomo)} — inservible');
        }
      });

      test('los rankings no se solapan', () async {
        final container = ProviderContainer(
          overrides: [databaseProvider.overrideWith((ref) async => base.db)],
        );
        addTearDown(container.dispose);

        final reporte = await container.read(
          reportesProvider(ReportesParametros(
            rango: RangoReporte.dia,
            fechaReferencia: DateTime(2020, 6, 15),
          )).future,
        );

        // Defecto que el usuario vio en pantalla: hoy `masVendidos` y
        // `menosVendidos` son el MISMO conjunto ordenado al revés, así que un
        // producto aparece en las dos listas a la vez. Dos listas que dicen
        // cosas opuestas del mismo producto no informan nada.
        final masTop = reporte.masVendidos.take(5).map((r) => r.nombre).toSet();
        final menosTop = reporte.menosVendidos.take(5).map((r) => r.nombre).toSet();
        final solapados = masTop.intersection(menosTop);

        _anotar(nivel.nombre, 'rankings solapados (top 5)', '${solapados.length}',
            solapados.isEmpty ? 'OK' : 'se repiten: ${solapados.join(", ")}');

        expect(solapados, isEmpty,
            reason: 'un producto no puede ser de los más Y de los menos vendidos');
      });

      test('listar el historial completo de ventas', () async {
        final dao = VentaDao(base.db);
        final rssAntes = rssMb();
        final (ventas, tomo) = await medir(() => dao.listar());
        final rssDespues = rssMb();

        _anotar(nivel.nombre, 'listar historial', ms(tomo), '${ventas.length} ventas');
        _anotar(nivel.nombre, 'listar historial RSS', '+${rssDespues - rssAntes} MB', '');

        // No hay presupuesto duro acá: sin paginación esto crece sin techo por
        // diseño, y el punto de la medición es justamente dimensionar cuánto.
        expect(tomo, lessThan(umbralCatastrofe));
      });
    });
  }
}
