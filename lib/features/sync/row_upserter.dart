import 'package:sqflite/sqflite.dart';

import 'row_sync_engine.dart';

/// Aplica un conjunto de filas remotas contra una tabla local, fila por
/// fila, usando [RowSyncEngine.resolver] para decidir el ganador por LWW.
///
/// Compartido entre `TiketdataService` (merge desde un archivo `.tiketdata`)
/// y `SyncClient` (merge desde un peer de red) — es la misma operación de
/// "aplicar filas remotas a esta base de datos" sin importar de dónde
/// vinieron, no se duplica la lógica en los dos lugares (decisión 0009: no
/// reciclar código entre conceptos distintos, pero esto SÍ es el mismo
/// concepto reutilizado legítimamente, no una entidad de negocio).
class RowUpserter {
  RowUpserter(this._db);

  final Database _db;
  final _rowSyncEngine = const RowSyncEngine();

  Future<void> aplicar(String tabla, List<Map<String, Object?>> remotas) async {
    for (final remota in remotas) {
      final id = remota['id'] as String;
      final localRows = await _db.query(tabla, where: 'id = ?', whereArgs: [id]);
      if (localRows.isEmpty) {
        await _db.insert(tabla, remota);
      } else {
        final ganadora = _rowSyncEngine.resolver(local: localRows.first, remota: remota);
        await _db.update(tabla, ganadora, where: 'id = ?', whereArgs: [id]);
      }
    }
  }
}
