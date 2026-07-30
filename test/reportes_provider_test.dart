import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vulp_tiketing/core/db/app_database.dart';
import 'package:vulp_tiketing/core/db/db_providers.dart';
import 'package:vulp_tiketing/features/reportes/reportes_provider.dart';

/// El reporte agrega en SQL, no en Dart — es lo que lo hizo viable (el reporte
/// del día pasó de 5.940 ms a 280 ms con un año de volumen real, y el anual de
/// no terminar en 4 minutos a 501 ms).
///
/// El costo de esa decisión es que la clasificación de turno existe DOS veces:
/// en `turnoDe` (Dart) y en un `CASE` de SQL. Estas pruebas son el precio de
/// esa duplicación: si alguien cambia un corte de turno en un lado y no en el
/// otro, fallan.
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
    await AppDatabase.crearEsquema(db);
    return db;
  }

  /// Siembra una venta de una línea a una hora dada del 2026-03-10.
  Future<void> sembrar(Database db, int hora, double precio, {String? productoId}) async {
    final fecha = DateTime(2026, 3, 10, hora, 15);
    final id = 'v-$hora-${precio.toInt()}-${productoId ?? "x"}';
    await db.insert('venta', {
      'id': id,
      'fecha_hora': fecha.toIso8601String(),
      'estado': 'activa',
      'updated_at': fecha.toIso8601String(),
    });
    await db.insert('linea_venta', {
      'id': 'l-$id',
      'venta_id': id,
      'producto_id': productoId,
      'nombre_libre': productoId == null ? 'linea libre' : null,
      'precio_aplicado': precio,
      'cantidad': 1,
      'updated_at': fecha.toIso8601String(),
    });
  }

  Future<ReporteResultado> reporteDelDia(Database db) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    return container.read(
      reportesProvider(ReportesParametros(
        rango: RangoReporte.dia,
        fechaReferencia: DateTime(2026, 3, 10),
      )).future,
    );
  }

  test('el CASE de SQL clasifica los turnos igual que turnoDe en Dart', () async {
    final db = await abrirDb();
    addTearDown(db.close);

    // Una venta por cada hora del día, con un precio que identifica la hora.
    for (var hora = 0; hora < 24; hora++) {
      await sembrar(db, hora, (100 + hora).toDouble(), productoId: null);
    }

    final reporte = await reporteDelDia(db);

    // Lo que Dart dice que debería sumar cada turno.
    final esperado = {for (final t in Turno.values) t: 0.0};
    for (var hora = 0; hora < 24; hora++) {
      final t = turnoDe(DateTime(2026, 3, 10, hora, 15));
      esperado[t] = esperado[t]! + (100 + hora).toDouble();
    }

    for (final t in Turno.values) {
      expect(
        reporte.porTurno[t],
        closeTo(esperado[t]!, 0.001),
        reason: 'turno ${t.name}: el CASE de SQL y turnoDe no coinciden',
      );
    }
  });

  test('las lineas libres cuentan para el total pero no para el ranking', () async {
    final db = await abrirDb();
    addTearDown(db.close);

    await db.insert('producto', {
      'id': 'p1',
      'nombre': 'Empanada',
      'precio_base': 900,
      'updated_at': DateTime(2026).toIso8601String(),
    });
    await sembrar(db, 10, 900, productoId: 'p1');
    await sembrar(db, 10, 5000); // linea libre

    final reporte = await reporteDelDia(db);

    // Decision 0016: el ranking es para decisiones de catalogo, y una linea
    // libre no es un producto de catalogo. Pero la plata entra igual.
    expect(reporte.total, closeTo(5900, 0.001));
    expect(reporte.masVendidos.map((r) => r.nombre), equals(['Empanada']));
  });

  test('ningun producto aparece en los dos rankings a la vez', () async {
    final db = await abrirDb();
    addTearDown(db.close);

    // Menos productos que el limite del ranking: es el caso que hacia que las
    // dos listas fueran el mismo conjunto y un producto saliera como el mas Y
    // el menos vendido. Es el defecto que se vio en pantalla.
    for (var i = 0; i < 3; i++) {
      await db.insert('producto', {
        'id': 'p$i',
        'nombre': 'Producto $i',
        'precio_base': 1000,
        'updated_at': DateTime(2026).toIso8601String(),
      });
      for (var v = 0; v <= i; v++) {
        await sembrar(db, 10 + v, 1000, productoId: 'p$i');
      }
    }

    final reporte = await reporteDelDia(db);
    final mas = reporte.masVendidos.map((r) => r.nombre).toSet();
    final menos = reporte.menosVendidos.map((r) => r.nombre).toSet();

    expect(mas.intersection(menos), isEmpty);
    expect(mas, isNotEmpty);
  });

  test('el drill-down solo se llena para el rango de dia', () async {
    final db = await abrirDb();
    addTearDown(db.close);

    await db.insert('producto', {
      'id': 'p1',
      'nombre': 'Cafe',
      'precio_base': 800,
      'updated_at': DateTime(2026).toIso8601String(),
    });
    await sembrar(db, 9, 800, productoId: 'p1');

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);

    final dia = await container.read(
      reportesProvider(ReportesParametros(
        rango: RangoReporte.dia,
        fechaReferencia: DateTime(2026, 3, 10),
      )).future,
    );
    final anio = await container.read(
      reportesProvider(ReportesParametros(
        rango: RangoReporte.anio,
        fechaReferencia: DateTime(2026, 3, 10),
      )).future,
    );

    // El dia lo necesita para el drill-down; el anio no lo usa y llenarlo
    // significaba retener en memoria todas las ventas del anio con sus lineas.
    expect(dia.ventasPorTurno[Turno.manana], hasLength(1));
    expect(anio.ventasPorTurno.values.every((l) => l.isEmpty), isTrue);
    // Pero el total del anio sigue siendo correcto.
    expect(anio.total, closeTo(800, 0.001));
  });
}
