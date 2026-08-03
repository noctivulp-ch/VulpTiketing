import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';

/// Qué períodos tienen ventas, para que el selector de fecha lo diga ANTES de
/// entrar.
///
/// Sin esto, elegir un período es a ciegas: se toca un día, se espera la carga
/// y aparece "sin ventas". En una soda que abre seis días por semana, buscar el
/// martes de hace tres semanas era prueba y error.
///
/// Se consulta por año y no día a día: son 365 filas como mucho, la consulta ya
/// agrupa en SQL, y con un solo viaje quedan resueltas las cuatro escalas —día,
/// semana, mes y año— sin una consulta por celda del calendario.
class PeriodosConDatos {
  const PeriodosConDatos({required this.dias});

  /// Los días con al menos una venta activa, como `2026-03-04`.
  final Set<String> dias;

  static const vacio = PeriodosConDatos(dias: {});

  bool tieneDia(DateTime dia) => dias.contains(_clave(dia));

  /// La semana del lunes al domingo que contiene [dia].
  bool tieneSemana(DateTime dia) {
    final lunes = dia.subtract(Duration(days: dia.weekday - 1));
    for (var i = 0; i < 7; i++) {
      if (tieneDia(lunes.add(Duration(days: i)))) return true;
    }
    return false;
  }

  bool tieneMes(int anio, int mes) {
    final prefijo = '$anio-${mes.toString().padLeft(2, '0')}';
    return dias.any((d) => d.startsWith(prefijo));
  }

  bool tieneAnio(int anio) => dias.any((d) => d.startsWith('$anio-'));

  static String _clave(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Los días con ventas de un año. Se pide por año porque el calendario se mueve
/// de mes en mes dentro del mismo año la mayor parte del tiempo, y así cambiar
/// de mes no dispara una consulta.
final periodosConDatosProvider = FutureProvider.family<PeriodosConDatos, int>((ref, anio) async {
  final db = await ref.watch(databaseProvider.future);
  final filas = await db.rawQuery(
    "SELECT DISTINCT substr(fecha_hora, 1, 10) AS dia FROM venta "
    "WHERE estado = 'activa' AND fecha_hora >= ? AND fecha_hora < ?",
    ['$anio-01-01T00:00:00.000', '${anio + 1}-01-01T00:00:00.000'],
  );
  return PeriodosConDatos(dias: {for (final f in filas) f['dia'] as String});
});

/// Los años que tienen alguna venta, para la lista de años.
///
/// Consulta aparte: la de arriba mira un año concreto, y para pintar la lista
/// hace falta saber de todos a la vez sin pedir uno por uno.
final aniosConVentasProvider = FutureProvider<Set<int>>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final filas = await db.rawQuery(
    "SELECT DISTINCT substr(fecha_hora, 1, 4) AS anio FROM venta WHERE estado = 'activa'",
  );
  return {for (final f in filas) int.parse(f['anio'] as String)};
});
