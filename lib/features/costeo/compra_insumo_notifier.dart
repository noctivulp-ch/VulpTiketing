import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db/db_providers.dart';
import '../venta/libro_ventas.dart';
import 'compra_insumo_model.dart';

/// Las compras de insumos: anotar, corregir, anular (0041). Escriben en el
/// libro adjunto, como las ventas: `compra_insumo` resuelve contra él.
///
/// No hay lista base en el estado: las compras se leen por rango a través de
/// los libros (`comprasDeInsumosProvider`), no todas a memoria. El estado es
/// un contador de versión para que quien lea se entere de que hubo cambio.
class CompraInsumoNotifier extends Notifier<int> {
  @override
  int build() => 0;

  Future<Database> get _db => ref.read(databaseProvider.future);

  Future<void> anotar(CompraInsumo compra) async {
    final db = await _db;
    // La compra va al libro que corresponda a su fecha (rota si hace falta),
    // igual que una venta.
    final libros = await ref.read(libroVentasServiceProvider.future);
    await libros.prepararPara(db, compra.fecha);
    await db.insert('compra_insumo', compra.toMap());
    state++;
  }

  Future<void> corregir(CompraInsumo compra) async {
    final db = await _db;
    await db.update('compra_insumo', compra.toMap(), where: 'id = ?', whereArgs: [compra.id]);
    state++;
  }

  /// Marca, no borra: el libro no se edita hacia atrás.
  Future<void> anular(String id) async {
    final db = await _db;
    final ahora = DateTime.now().toIso8601String();
    await db.update('compra_insumo', {'deleted_at': ahora, 'updated_at': ahora}, where: 'id = ?', whereArgs: [id]);
    state++;
  }
}

final compraInsumoNotifierProvider = NotifierProvider<CompraInsumoNotifier, int>(CompraInsumoNotifier.new);
