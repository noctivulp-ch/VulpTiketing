import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import 'categoria_dao.dart';
import 'categoria_model.dart';

/// Mismo patron que ProductoNotifier, ciclo de vida propio (decision 0009):
/// crear, leer, actualizar, descontinuar. Sin purgar todavia — no se pidio
/// para Categoria, no asumir que aplica igual que a Producto (0015 fue
/// especifico de Producto).
class CategoriaNotifier extends AsyncNotifier<List<Categoria>> {
  late final CategoriaDao _dao;

  @override
  Future<List<Categoria>> build() async {
    final db = await ref.watch(databaseProvider.future);
    _dao = CategoriaDao(db);
    return _dao.listarActivas();
  }

  Future<void> crear(Categoria categoria) async {
    await _dao.insertar(categoria);
    state = AsyncData(await _dao.listarActivas());
  }

  Future<void> actualizar(Categoria categoria) async {
    await _dao.actualizar(categoria);
    state = AsyncData(await _dao.listarActivas());
  }

  Future<void> descontinuar(String id) async {
    await _dao.descontinuar(id, DateTime.now());
    state = AsyncData(await _dao.listarActivas());
  }
}

final categoriaNotifierProvider =
    AsyncNotifierProvider<CategoriaNotifier, List<Categoria>>(
  CategoriaNotifier.new,
);
