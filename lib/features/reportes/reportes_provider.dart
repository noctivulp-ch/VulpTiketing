import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import '../venta/linea_venta_model.dart';
import '../venta/venta_model.dart';

/// Solo lectura, se deriva de Venta/LineaVenta — ver
/// docs/arquitectura/gestion-estado.md. Ningún estado propio que mutar.

enum RangoReporte { dia, semana, mes, anio }

enum Turno { manana, tarde, noche }

Turno turnoDe(DateTime fechaHora) {
  final hora = fechaHora.hour;
  if (hora < 12) return Turno.manana;
  if (hora < 18) return Turno.tarde;
  return Turno.noche;
}

class ReportesParametros {
  const ReportesParametros({required this.rango, required this.fechaReferencia});

  final RangoReporte rango;
  final DateTime fechaReferencia;

  @override
  bool operator ==(Object other) =>
      other is ReportesParametros &&
      other.rango == rango &&
      other.fechaReferencia.year == fechaReferencia.year &&
      other.fechaReferencia.month == fechaReferencia.month &&
      other.fechaReferencia.day == fechaReferencia.day;

  @override
  int get hashCode => Object.hash(rango, fechaReferencia.year, fechaReferencia.month, fechaReferencia.day);
}

class VentaConLineas {
  const VentaConLineas({required this.venta, required this.lineas});
  final Venta venta;
  final List<LineaVenta> lineas;

  double get total => lineas.fold(0, (s, l) => s + l.precioAplicado * l.cantidad);
}

class RankingItem {
  const RankingItem({required this.nombre, required this.cantidad});
  final String nombre;
  final int cantidad;
}

class ReporteResultado {
  const ReporteResultado({
    required this.total,
    required this.porTurno,
    required this.masVendidos,
    required this.menosVendidos,
    required this.ventasPorTurno,
  });

  final double total;
  final Map<Turno, double> porTurno;
  final List<RankingItem> masVendidos;
  final List<RankingItem> menosVendidos;

  /// Solo poblado cuando rango == dia — es la base del drill-down.
  final Map<Turno, List<VentaConLineas>> ventasPorTurno;
}

(DateTime, DateTime) rangoDeFechas(RangoReporte rango, DateTime referencia) {
  final diaBase = DateTime(referencia.year, referencia.month, referencia.day);
  switch (rango) {
    case RangoReporte.dia:
      return (diaBase, diaBase.add(const Duration(days: 1)));
    case RangoReporte.semana:
      final inicio = diaBase.subtract(Duration(days: diaBase.weekday - 1));
      return (inicio, inicio.add(const Duration(days: 7)));
    case RangoReporte.mes:
      final inicio = DateTime(referencia.year, referencia.month);
      final siguiente = referencia.month == 12
          ? DateTime(referencia.year + 1)
          : DateTime(referencia.year, referencia.month + 1);
      return (inicio, siguiente);
    case RangoReporte.anio:
      return (DateTime(referencia.year), DateTime(referencia.year + 1));
  }
}

/// Cuántos productos entran en cada ranking. Antes no había límite: las dos
/// listas eran el catálogo completo ordenado al revés, así que un mismo
/// producto salía en "más vendidos" Y en "menos vendidos" a la vez.
const limiteRanking = 10;

/// Fragmento SQL que clasifica una fila de venta en su turno. Duplica la
/// lógica de [turnoDe] a propósito, porque agregar en SQL es lo que hace
/// viable el reporte: traer las filas a Dart para clasificarlas costaba
/// segundos con un año de datos. Los cortes son los mismos (decisión 0003) y
/// hay una prueba que compara las dos implementaciones fila por fila.
const _sqlTurno = '''
  CASE
    WHEN CAST(strftime('%H', v.fecha_hora) AS INTEGER) < 12 THEN 'manana'
    WHEN CAST(strftime('%H', v.fecha_hora) AS INTEGER) < 18 THEN 'tarde'
    ELSE 'noche'
  END''';

const _sqlRangoActivo =
    "v.estado = 'activa' AND v.fecha_hora >= ? AND v.fecha_hora < ?";

Turno _turnoDeNombre(String nombre) => switch (nombre) {
      'manana' => Turno.manana,
      'tarde' => Turno.tarde,
      _ => Turno.noche,
    };

/// Agrega en SQL, no en Dart.
///
/// La versión anterior traía todas las ventas del rango y hacía UNA CONSULTA
/// POR VENTA para sus líneas, más una consulta por producto para su nombre. Con
/// un año de volumen real (117 k ventas, 234 k líneas) y sin índices, el
/// reporte del día tardaba 5,9 s y el del año no terminaba en 4 minutos: el día
/// escaneaba 320 × 234 k filas, y el año 117 k × 234 k ≈ 27 mil millones.
///
/// Ahora son tres consultas agregadas de tamaño fijo, más el drill-down solo
/// cuando hace falta.
final reportesProvider =
    FutureProvider.family<ReporteResultado, ReportesParametros>((ref, params) async {
  final db = await ref.watch(databaseProvider.future);

  final (desde, hasta) = rangoDeFechas(params.rango, params.fechaReferencia);
  final args = [desde.toIso8601String(), hasta.toIso8601String()];

  // 1. Totales por turno. El total general es su suma, así no hace falta una
  //    cuarta consulta.
  final totalesRows = await db.rawQuery('''
    SELECT $_sqlTurno AS turno,
           SUM(lv.precio_aplicado * lv.cantidad) AS total
    FROM linea_venta lv
    JOIN venta v ON v.id = lv.venta_id
    WHERE $_sqlRangoActivo
    GROUP BY turno
  ''', args);

  final porTurno = {for (final t in Turno.values) t: 0.0};
  for (final row in totalesRows) {
    porTurno[_turnoDeNombre(row['turno'] as String)] =
        (row['total'] as num?)?.toDouble() ?? 0;
  }
  final total = porTurno.values.fold(0.0, (a, b) => a + b);

  // 2. Ranking, con el nombre resuelto en la misma consulta (antes era una
  //    consulta por producto distinto). Las líneas libres quedan fuera a
  //    propósito: el ranking existe para decisiones de catálogo, y una línea
  //    libre por definición no es un producto de catálogo (decisión 0016).
  //    Sí cuentan para el total de dinero, solo no para "qué producto vender".
  final rankingRows = await db.rawQuery('''
    SELECT lv.producto_id AS id,
           COALESCE(p.nombre, 'Producto eliminado') AS nombre,
           SUM(lv.cantidad) AS cantidad
    FROM linea_venta lv
    JOIN venta v ON v.id = lv.venta_id
    LEFT JOIN producto p ON p.id = lv.producto_id
    WHERE $_sqlRangoActivo AND lv.producto_id IS NOT NULL
    GROUP BY lv.producto_id
    ORDER BY cantidad DESC
  ''', args);

  final masVendidos = <RankingItem>[];
  final idsEnMas = <String>{};
  for (final row in rankingRows.take(limiteRanking)) {
    idsEnMas.add(row['id'] as String);
    masVendidos.add(RankingItem(
      nombre: row['nombre'] as String,
      cantidad: (row['cantidad'] as num).toInt(),
    ));
  }

  // Los menos vendidos se toman desde la cola, excluyendo lo que ya está en
  // "más vendidos": dos listas que afirman lo contrario del mismo producto no
  // informan nada.
  final menosVendidos = <RankingItem>[];
  for (final row in rankingRows.reversed) {
    if (menosVendidos.length >= limiteRanking) break;
    if (idsEnMas.contains(row['id'] as String)) continue;
    menosVendidos.add(RankingItem(
      nombre: row['nombre'] as String,
      cantidad: (row['cantidad'] as num).toInt(),
    ));
  }

  // 3. Drill-down: SOLO para el rango de día, como ya decía la documentación
  //    de `ventasPorTurno`. Llenarlo siempre hacía que un reporte anual
  //    retuviera en memoria todas las ventas del año con todas sus líneas.
  final ventasPorTurno = {for (final t in Turno.values) t: <VentaConLineas>[]};
  if (params.rango == RangoReporte.dia) {
    final ventasRows = await db.query(
      'venta',
      where: 'estado = ? AND fecha_hora >= ? AND fecha_hora < ?',
      whereArgs: ['activa', ...args],
    );
    // Todas las líneas del rango en UNA consulta, agrupadas en Dart — no una
    // consulta por venta.
    final lineasRows = await db.rawQuery('''
      SELECT lv.* FROM linea_venta lv
      JOIN venta v ON v.id = lv.venta_id
      WHERE $_sqlRangoActivo
    ''', args);

    final lineasPorVenta = <String, List<LineaVenta>>{};
    for (final row in lineasRows) {
      (lineasPorVenta[row['venta_id'] as String] ??= [])
          .add(LineaVenta.fromMap(row));
    }

    for (final row in ventasRows) {
      final venta = Venta.fromMap(row);
      final vc = VentaConLineas(
        venta: venta,
        lineas: lineasPorVenta[venta.id] ?? const [],
      );
      ventasPorTurno[turnoDe(venta.fechaHora)]!.add(vc);
    }
  }

  return ReporteResultado(
    total: total,
    porTurno: porTurno,
    masVendidos: masVendidos,
    menosVendidos: menosVendidos,
    ventasPorTurno: ventasPorTurno,
  );
});
