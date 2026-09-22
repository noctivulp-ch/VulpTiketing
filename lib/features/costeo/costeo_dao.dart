import 'package:sqflite/sqflite.dart';

import 'articulo_costeo_model.dart';
import 'config_costeo_model.dart';
import 'costo_fijo_model.dart';
import 'insumo_model.dart';

/// Filas de las cinco tablas del costeo, sin reglas. Un DAO por tabla sería
/// cinco archivos de veinte líneas iguales; acá van juntos pero cada bloque
/// es de su tabla y nada más — el Notifier de cada entidad usa solo el suyo.
class CosteoDao {
  CosteoDao(this._db);

  final DatabaseExecutor _db;

  // ── insumo ──────────────────────────────────────────────────────────────
  Future<List<InsumoRegistro>> listarInsumos() async =>
      (await _db.query('insumo', orderBy: 'nombre COLLATE NOCASE')).map(InsumoRegistro.fromMap).toList();

  Future<void> insertarInsumo(InsumoRegistro i) => _db.insert('insumo', i.toMap());

  Future<void> actualizarInsumo(InsumoRegistro i) =>
      _db.update('insumo', i.toMap(), where: 'id = ?', whereArgs: [i.id]);

  Future<void> descontinuarInsumo(String id, DateTime cuando) => _marcar('insumo', id, cuando);

  // ── costo_fijo ──────────────────────────────────────────────────────────
  Future<List<CostoFijoRegistro>> listarCostosFijos() async =>
      (await _db.query('costo_fijo', orderBy: 'concepto COLLATE NOCASE')).map(CostoFijoRegistro.fromMap).toList();

  Future<void> insertarCostoFijo(CostoFijoRegistro c) => _db.insert('costo_fijo', c.toMap());

  Future<void> actualizarCostoFijo(CostoFijoRegistro c) =>
      _db.update('costo_fijo', c.toMap(), where: 'id = ?', whereArgs: [c.id]);

  Future<void> descontinuarCostoFijo(String id, DateTime cuando) => _marcar('costo_fijo', id, cuando);

  // ── config_costeo ───────────────────────────────────────────────────────
  Future<ConfigCosteoRegistro?> leerConfig() async {
    final filas = await _db.query('config_costeo', where: 'id = ?', whereArgs: [ConfigCosteoRegistro.idUnica]);
    return filas.isEmpty ? null : ConfigCosteoRegistro.fromMap(filas.first);
  }

  Future<void> guardarConfig(ConfigCosteoRegistro c) =>
      _db.insert('config_costeo', c.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  // ── articulo_costeo ─────────────────────────────────────────────────────
  Future<List<ArticuloCosteoRegistro>> listarArticulos() async =>
      (await _db.query('articulo_costeo')).map(ArticuloCosteoRegistro.fromMap).toList();

  Future<void> guardarArticulo(ArticuloCosteoRegistro a) =>
      _db.insert('articulo_costeo', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  // ── linea_receta ────────────────────────────────────────────────────────
  Future<List<LineaRecetaRegistro>> listarLineas() async =>
      (await _db.query('linea_receta')).map(LineaRecetaRegistro.fromMap).toList();

  Future<void> guardarLinea(LineaRecetaRegistro l) =>
      _db.insert('linea_receta', l.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> descontinuarLinea(String id, DateTime cuando) => _marcar('linea_receta', id, cuando);

  Future<void> _marcar(String tabla, String id, DateTime cuando) => _db.update(
    tabla,
    {'deleted_at': cuando.toIso8601String(), 'updated_at': cuando.toIso8601String()},
    where: 'id = ?',
    whereArgs: [id],
  );
}
