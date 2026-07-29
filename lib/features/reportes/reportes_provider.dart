import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import '../producto/producto_dao.dart';
import '../venta/linea_venta_model.dart';
import '../venta/venta_dao.dart';
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

final reportesProvider =
    FutureProvider.family<ReporteResultado, ReportesParametros>((ref, params) async {
  final db = await ref.watch(databaseProvider.future);
  final ventaDao = VentaDao(db);
  final productoDao = ProductoDao(db);

  final (desde, hasta) = rangoDeFechas(params.rango, params.fechaReferencia);

  final ventasRows = await db.query(
    'venta',
    where: 'estado = ? AND fecha_hora >= ? AND fecha_hora < ?',
    whereArgs: ['activa', desde.toIso8601String(), hasta.toIso8601String()],
  );

  final ventasConLineas = <VentaConLineas>[];
  for (final row in ventasRows) {
    final venta = Venta.fromMap(row);
    final lineas = await ventaDao.lineasDe(venta.id);
    ventasConLineas.add(VentaConLineas(venta: venta, lineas: lineas));
  }

  double total = 0;
  final porTurno = {for (final t in Turno.values) t: 0.0};
  final ventasPorTurno = {for (final t in Turno.values) t: <VentaConLineas>[]};
  // productoId/nombreLibre -> cantidad vendida. Lineas libres se excluyen
  // del ranking a proposito: el ranking existe para decisiones de catalogo
  // (que producto vender mas/menos), y una linea libre por definicion no
  // es un producto de catalogo (decision 0016). Si cuentan para el total
  // de dinero, solo no para "que producto vender mas".
  final cantidadPorProducto = <String, int>{};
  final nombreCache = <String, String>{};

  for (final vc in ventasConLineas) {
    total += vc.total;
    final turno = turnoDe(vc.venta.fechaHora);
    porTurno[turno] = (porTurno[turno] ?? 0) + vc.total;
    ventasPorTurno[turno]!.add(vc);

    for (final linea in vc.lineas) {
      if (linea.productoId == null) continue; // linea libre, fuera del ranking
      cantidadPorProducto[linea.productoId!] =
          (cantidadPorProducto[linea.productoId!] ?? 0) + linea.cantidad;
    }
  }

  for (final id in cantidadPorProducto.keys) {
    if (nombreCache.containsKey(id)) continue;
    final producto = await productoDao.obtenerPorId(id);
    nombreCache[id] = producto?.nombre ?? 'Producto eliminado';
  }

  final items = [
    for (final entry in cantidadPorProducto.entries)
      RankingItem(nombre: nombreCache[entry.key]!, cantidad: entry.value),
  ];
  final masVendidos = [...items]..sort((a, b) => b.cantidad.compareTo(a.cantidad));
  final menosVendidos = [...items]..sort((a, b) => a.cantidad.compareTo(b.cantidad));

  return ReporteResultado(
    total: total,
    porTurno: porTurno,
    masVendidos: masVendidos,
    menosVendidos: menosVendidos,
    ventasPorTurno: ventasPorTurno,
  );
});
