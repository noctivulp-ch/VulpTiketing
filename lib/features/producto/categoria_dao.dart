import 'package:sqflite/sqflite.dart';

import 'categoria_model.dart';

/// Acceso a datos crudo de Categoria — mismo patron que ProductoDao.
class CategoriaDao {
  CategoriaDao(this._db);

  final Database _db;

  Future<List<Categoria>> listarActivas() async {
    final rows = await _db.query('categoria', where: 'deleted_at IS NULL');
    return rows.map(Categoria.fromMap).toList();
  }

  Future<void> insertar(Categoria categoria) {
    return _db.insert('categoria', categoria.toMap());
  }

  Future<void> actualizar(Categoria categoria) {
    return _db.update(
      'categoria',
      categoria.toMap(),
      where: 'id = ?',
      whereArgs: [categoria.id],
    );
  }

  Future<void> descontinuar(String id, DateTime cuando) {
    return _db.update(
      'categoria',
      {'deleted_at': cuando.toIso8601String(), 'updated_at': cuando.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
