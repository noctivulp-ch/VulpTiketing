import 'package:sqflite/sqflite.dart';

import 'producto_model.dart';

/// Acceso a datos crudo de Producto. Sin logica de negocio (eso vive en
/// ProductoNotifier) — este DAO solo sabe leer/escribir filas.
class ProductoDao {
  ProductoDao(this._db);

  final Database _db;

  Future<List<Producto>> listarActivos() async {
    final rows = await _db.query(
      'producto',
      where: 'deleted_at IS NULL',
    );
    return rows.map(Producto.fromMap).toList();
  }

  /// Incluye descontinuados a propósito — Reportes necesita poder resolver
  /// el nombre de un producto que ya no está en el catálogo activo pero
  /// aparece en ventas históricas. (Un producto purgado nunca llega aquí:
  /// 0015 garantiza que purgar exige cero ventas asociadas.)
  Future<Producto?> obtenerPorId(String id) async {
    final rows = await _db.query('producto', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Producto.fromMap(rows.first);
  }

  Future<void> insertar(Producto producto) {
    return _db.insert('producto', producto.toMap());
  }

  Future<void> actualizar(Producto producto) {
    return _db.update(
      'producto',
      producto.toMap(),
      where: 'id = ?',
      whereArgs: [producto.id],
    );
  }

  /// Soft-delete (decision 0005) — nunca borra la fila fisicamente.
  Future<void> descontinuar(String id, DateTime cuando) {
    return _db.update(
      'producto',
      {'deleted_at': cuando.toIso8601String(), 'updated_at': cuando.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cuantas LineaVenta referencian este producto — precondicion de purgar
  /// (decision 0015). El gate de "todos los dispositivos sincronizados"
  /// se resuelve en ProductoNotifier consultando SyncNotifier, no aqui.
  Future<int> contarVentasAsociadas(String productoId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS total FROM linea_venta WHERE producto_id = ?',
      [productoId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Borrado fisico real — solo llamar despues de validar las 3 condiciones
  /// de la decision 0015 (descontinuado + cero ventas + sync confirmado).
  Future<void> purgar(String id) {
    return _db.delete('producto', where: 'id = ?', whereArgs: [id]);
  }
}
