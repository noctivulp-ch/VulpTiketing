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

  /// Todo el lote va en UNA transacción, por dos razones distintas:
  ///
  /// 1. **Atomicidad.** Sin transacción, un fallo a mitad de camino dejaba la
  ///    base con medio sync aplicado: unas filas nuevas y otras no, sin forma
  ///    de saber cuáles. Un merge a medias es peor que un merge que no ocurrió.
  /// 2. **Velocidad.** Cada sentencia suelta es su propia transacción implícita
  ///    con su propio commit y fsync. Aplicar un sync de cientos de miles de
  ///    filas eran cientos de miles de commits al disco.
  ///
  /// Sigue siendo un SELECT por fila para resolver el LWW. Eso es O(n)
  /// consultas, pero cada una es un lookup por clave primaria — barato — y
  /// permite delegar la decisión a [RowSyncEngine] sin duplicar su lógica en
  /// SQL. Si el volumen lo exige, el paso siguiente es traer las locales del
  /// lote en una sola consulta `WHERE id IN (...)`; se decide con mediciones,
  /// no por adelantado.
  Future<void> aplicar(String tabla, List<Map<String, Object?>> remotas) async {
    if (remotas.isEmpty) return;

    await _db.transaction((txn) async {
      for (final remota in remotas) {
        final id = remota['id'] as String;
        final localRows = await txn.query(tabla, where: 'id = ?', whereArgs: [id]);
        if (localRows.isEmpty) {
          await txn.insert(tabla, remota);
        } else {
          final ganadora = _rowSyncEngine.resolver(local: localRows.first, remota: remota);
          await txn.update(tabla, ganadora, where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }
}
