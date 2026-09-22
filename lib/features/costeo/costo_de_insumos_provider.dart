import 'package:costeo/costeo.dart' as c;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import '../venta/lectura_de_libros.dart';
import '../venta/libro_ventas.dart';
import 'compra_insumo_model.dart';
import 'compra_insumo_notifier.dart';
import 'costeo_notifiers.dart';
import 'insumo_model.dart';

/// Cuántos días hacia atrás se promedian las compras para el costo actual.
/// Noventa amortigua los saltos y sigue al mercado (0041 §3).
const diasDeCostoPromedio = 90;

enum OrigenDelCosto {
  promedio('promedio de compras de $diasDeCostoPromedio días'),
  ultimaCompra('última compra, hace más de $diasDeCostoPromedio días'),
  arranque('precio de arranque: todavía sin compras');

  const OrigenDelCosto(this.texto);
  final String texto;
}

/// El costo por unidad base de un insumo, y de dónde salió.
class CostoDeInsumo {
  const CostoDeInsumo({required this.costoPorUnidadBase, required this.origen, this.ultimaCompra});
  final double costoPorUnidadBase;
  final OrigenDelCosto origen;
  final DateTime? ultimaCompra;
}

/// Las compras de un rango, de todos los libros que lo crucen, más
/// recientes primero.
final comprasDeInsumosProvider = FutureProvider.family<List<CompraInsumo>, (DateTime, DateTime)>((ref, rango) async {
  ref.watch(compraInsumoNotifierProvider); // se rehace al anotar
  final db = await ref.watch(databaseProvider.future);
  final lector = LectorDeLibros(db, () => ref.read(libroVentasServiceProvider.future));
  final (desde, hasta) = rango;
  final compras = <CompraInsumo>[];
  for (final filas in await lector.enCadaLibro(desde, hasta, (e) => db.rawQuery(
    'SELECT * FROM $e.compra_insumo WHERE deleted_at IS NULL AND fecha >= ? AND fecha < ? ORDER BY fecha DESC',
    [desde.toIso8601String(), hasta.toIso8601String()],
  ))) {
    compras.addAll(filas.map(CompraInsumo.fromMap));
  }
  compras.sort((a, b) => b.fecha.compareTo(a.fecha));
  return compras;
});

/// Total pagado en compras en un rango. Es la cifra del simplificado
/// (`compras del trimestre × factor`) y la de "cuánto se gasta".
final totalComprasProvider = FutureProvider.family<double, (DateTime, DateTime)>((ref, rango) async {
  final compras = await ref.watch(comprasDeInsumosProvider(rango).future);
  return compras.fold<double>(0.0, (suma, compra) => suma + compra.pagado);
});

/// El costo actual de cada insumo activo, por id (0041 §3).
final costoDeInsumosProvider = FutureProvider<Map<String, CostoDeInsumo>>((ref) async {
  ref.watch(compraInsumoNotifierProvider);
  final insumos = await ref.watch(insumoNotifierProvider.future);
  final db = await ref.watch(databaseProvider.future);
  final lector = LectorDeLibros(db, () => ref.read(libroVentasServiceProvider.future));
  final hoy = DateTime.now();
  final manana = DateTime(hoy.year, hoy.month, hoy.day + 1);
  final desde = manana.subtract(const Duration(days: diasDeCostoPromedio));

  // Ventana: Σ pagado y Σ unidades por insumo.
  final pagado = <String, double>{};
  final unidades = <String, double>{};
  for (final filas in await lector.enCadaLibro(desde, manana, (e) => db.rawQuery(
    'SELECT insumo_id, SUM(pagado) AS pagado, SUM(presentaciones * contenido) AS unidades '
    'FROM $e.compra_insumo WHERE deleted_at IS NULL AND fecha >= ? AND fecha < ? GROUP BY insumo_id',
    [desde.toIso8601String(), manana.toIso8601String()],
  ))) {
    for (final f in filas) {
      final id = f['insumo_id'] as String;
      pagado[id] = (pagado[id] ?? 0) + (f['pagado'] as num).toDouble();
      unidades[id] = (unidades[id] ?? 0) + (f['unidades'] as num).toDouble();
    }
  }

  // Última compra de cada insumo, de cualquier fecha: para los que no tienen
  // ninguna en la ventana. Todos los libros.
  final ultima = <String, CompraInsumo>{};
  for (final filas in await lector.enCadaLibro(DateTime(2000), manana, (e) => db.rawQuery(
    'SELECT c.* FROM $e.compra_insumo c '
    'WHERE c.deleted_at IS NULL AND c.fecha = (SELECT MAX(fecha) FROM $e.compra_insumo x WHERE x.insumo_id = c.insumo_id AND x.deleted_at IS NULL)',
  ))) {
    for (final f in filas) {
      final compra = CompraInsumo.fromMap(f);
      final previa = ultima[compra.insumoId];
      if (previa == null || compra.fecha.isAfter(previa.fecha)) ultima[compra.insumoId] = compra;
    }
  }

  final resultado = <String, CostoDeInsumo>{};
  for (final i in insumos) {
    if (!i.activo) continue;
    final u = unidades[i.id] ?? 0;
    if (u > 0) {
      resultado[i.id] = CostoDeInsumo(
        costoPorUnidadBase: pagado[i.id]! / u,
        origen: OrigenDelCosto.promedio,
        ultimaCompra: ultima[i.id]?.fecha,
      );
    } else if (ultima[i.id] case final ult?) {
      resultado[i.id] = CostoDeInsumo(
        costoPorUnidadBase: ult.costoUnitario,
        origen: OrigenDelCosto.ultimaCompra,
        ultimaCompra: ult.fecha,
      );
    } else {
      resultado[i.id] = CostoDeInsumo(
        costoPorUnidadBase: i.puro.costoPorUnidadBase,
        origen: OrigenDelCosto.arranque,
      );
    }
  }
  return resultado;
});

/// El insumo puro que consume el cálculo, con el costo que manda hoy.
c.Insumo insumoConCosto(InsumoRegistro registro, CostoDeInsumo? costo) => c.Insumo(
  id: registro.id,
  nombre: registro.nombre,
  unidadBase: registro.unidadBase,
  // Una unidad base al costo actual: el cálculo solo mira el cociente.
  contenidoPorCompra: 1,
  precioCompra: costo?.costoPorUnidadBase ?? registro.puro.costoPorUnidadBase,
  merma: registro.merma,
);
