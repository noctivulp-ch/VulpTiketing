import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import 'producto_dao.dart';
import 'producto_model.dart';

enum PurgarResultado { ok, tieneVentasAsociadas, faltaSincronizar }

/// Solo escritura + lectura base (decision 0019) — el orden/busqueda de
/// presentacion vive en ProductoQueryProvider, no aqui.
class ProductoNotifier extends AsyncNotifier<List<Producto>> {
  // `late` sin `final`: Riverpod reutiliza esta misma instancia de Notifier
  // y vuelve a llamar build() cada vez que se invalida este provider o su
  // dependencia (databaseProvider) — con `final` la segunda asignacion
  // tiraba LateInitializationError ("ya estaba inicializado") apenas se
  // invalidaba este provider desde otro lado (ej. tras importar catalogo).
  late ProductoDao _dao;

  @override
  Future<List<Producto>> build() async {
    final db = await ref.watch(databaseProvider.future);
    _dao = ProductoDao(db);
    return _dao.listarActivos();
  }

  Future<void> crear(Producto producto) async {
    await _dao.insertar(producto);
    state = AsyncData(await _dao.listarActivos());
  }

  Future<void> actualizar(Producto producto) async {
    await _dao.actualizar(producto);
    state = AsyncData(await _dao.listarActivos());
  }

  /// Soft-delete (decision 0005) — nunca borrado fisico.
  Future<void> descontinuar(String id) async {
    await _dao.descontinuar(id, DateTime.now());
    state = AsyncData(await _dao.listarActivos());
  }

  /// Borrado fisico real, solo si se cumplen las 3 condiciones de la
  /// decision 0015. El gate de sync se recibe como parametro en vez de
  /// leerse aqui adentro, para no acoplar este Notifier a SyncNotifier
  /// (decision 0019) — quien llama decide de donde sale ese booleano.
  Future<PurgarResultado> purgar(
    String id, {
    required bool todosLosDispositivosSincronizados,
  }) async {
    final ventasAsociadas = await _dao.contarVentasAsociadas(id);
    if (ventasAsociadas > 0) return PurgarResultado.tieneVentasAsociadas;
    if (!todosLosDispositivosSincronizados) {
      return PurgarResultado.faltaSincronizar;
    }

    await _dao.purgar(id);
    state = AsyncData(await _dao.listarActivos());
    return PurgarResultado.ok;
  }
}

final productoNotifierProvider =
    AsyncNotifierProvider<ProductoNotifier, List<Producto>>(
  ProductoNotifier.new,
);
