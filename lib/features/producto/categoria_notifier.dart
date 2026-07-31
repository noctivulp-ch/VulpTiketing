import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import 'categoria_dao.dart';
import 'categoria_model.dart';

/// Mismo patron que ProductoNotifier, ciclo de vida propio (decision 0009):
/// crear, leer, actualizar, descontinuar. Sin purgar todavia — no se pidio
/// para Categoria, no asumir que aplica igual que a Producto (0015 fue
/// especifico de Producto).
class CategoriaNotifier extends AsyncNotifier<List<Categoria>> {
  /// Ver el comentario equivalente en ProductoNotifier: el DAO se resuelve en
  /// cada llamada, nunca se guarda en un campo.
  Future<CategoriaDao> get _dao async => CategoriaDao(await ref.read(databaseProvider.future));

  @override
  Future<List<Categoria>> build() async {
    final db = await ref.watch(databaseProvider.future);
    return CategoriaDao(db).listarActivas();
  }

  Future<void> crear(Categoria categoria) async {
    final dao = await _dao;
    await dao.insertar(categoria);
    state = AsyncData(await dao.listarActivas());
  }

  Future<void> actualizar(Categoria categoria) async {
    final dao = await _dao;
    await dao.actualizar(categoria);
    state = AsyncData(await dao.listarActivas());
  }

  Future<void> descontinuar(String id) async {
    final dao = await _dao;
    await dao.descontinuar(id, DateTime.now());
    state = AsyncData(await dao.listarActivas());
  }
}

final categoriaNotifierProvider = AsyncNotifierProvider<CategoriaNotifier, List<Categoria>>(
  CategoriaNotifier.new,
);
