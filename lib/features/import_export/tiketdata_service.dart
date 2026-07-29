import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../sync/row_sync_engine.dart';

enum ModoImportacion { reemplazar, fusionar }

/// Exportar/importar el paquete de catálogo `.tiketdata` (decisión 0017):
/// solo Producto y Categoria (nunca Ventas), JSON sin cifrar, preservando
/// los UUID originales de cada fila.
///
/// Reutiliza [RowSyncEngine] para el merge — el mismo motor que usa la sync
/// entre dispositivos (0019), no una copia de esa lógica.
class TiketdataService {
  TiketdataService(this._db);

  final Database _db;
  final _rowSyncEngine = const RowSyncEngine();

  /// Solo categorías/productos activos — un catálogo compartido no debería
  /// incluir ítems ya descontinuados en el negocio de origen.
  Future<void> exportarCatalogo(String rutaDestino) async {
    final categorias = await _db.query('categoria', where: 'deleted_at IS NULL');
    final productos = await _db.query('producto', where: 'deleted_at IS NULL');
    final json = jsonEncode({'categorias': categorias, 'productos': productos});
    await File(rutaDestino).writeAsString(json);
  }

  Future<void> importarCatalogo({
    required String rutaOrigen,
    required ModoImportacion modo,
  }) async {
    final contenido = jsonDecode(await File(rutaOrigen).readAsString()) as Map<String, dynamic>;
    final categoriasIncoming = _comoFilas(contenido['categorias']);
    final productosIncoming = _comoFilas(contenido['productos']);

    // Orden importa: categorias primero porque producto.categoria_id las
    // referencia.
    await _upsertConLww('categoria', categoriasIncoming);
    await _upsertConLww('producto', productosIncoming);

    if (modo == ModoImportacion.reemplazar) {
      await _descontinuarAusentes('producto', productosIncoming);
      await _descontinuarAusentes('categoria', categoriasIncoming);
    }
  }

  List<Map<String, Object?>> _comoFilas(dynamic lista) {
    return List<Map<String, Object?>>.from(
      (lista as List).map((fila) => Map<String, Object?>.from(fila as Map)),
    );
  }

  /// Upsert fila por fila usando RowSyncEngine.resolver — mismo mecanismo
  /// LWW que la sync entre dispositivos, aplicado aquí contra un archivo
  /// en vez de un peer de red.
  Future<void> _upsertConLww(String tabla, List<Map<String, Object?>> remotas) async {
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

  /// Modo "Reemplazar" (0017): descontinúa (soft-delete, nunca borrado
  /// físico — 0005) todo lo local activo que no venga en el archivo.
  Future<void> _descontinuarAusentes(String tabla, List<Map<String, Object?>> incoming) async {
    final idsPresentes = incoming.map((f) => f['id'] as String).toSet();
    final ahora = DateTime.now().toIso8601String();
    final localesActivas = await _db.query(tabla, where: 'deleted_at IS NULL');
    for (final fila in localesActivas) {
      final id = fila['id'] as String;
      if (!idsPresentes.contains(id)) {
        await _db.update(
          tabla,
          {'deleted_at': ahora, 'updated_at': ahora},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }
}
