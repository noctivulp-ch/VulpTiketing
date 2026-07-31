import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import 'producto_dao.dart';
import 'producto_model.dart';

enum PurgarResultado { ok, tieneVentasAsociadas, faltaSincronizar }

/// Solo escritura + lectura base (decision 0019) — el orden/busqueda de
/// presentacion vive en ProductoQueryProvider, no aqui.
class ProductoNotifier extends AsyncNotifier<List<Producto>> {
  /// El DAO se resuelve en CADA llamada; nunca se guarda en un campo.
  ///
  /// Guardarlo en un campo asignado dentro de `build()` producia
  /// `database_closed` en la primera operacion despues de restaurar un backup.
  /// Restaurar cierra la conexion (hay que reemplazar el archivo) e invalida
  /// `databaseProvider`, pero la reconstruccion de Riverpod es ASINCRONA: leer
  /// `.notifier` devuelve esta misma instancia con el campo viejo, apuntando a
  /// la conexion cerrada, porque `build()` todavia no volvio a correr. La
  /// segunda llamada ya funcionaba, asi que en uso real se veia como "fallo una
  /// vez y despues anduvo" — el peor tipo de fallo para diagnosticar.
  ///
  /// Es el tercer bug de la misma familia en este proyecto (ver
  /// docs/arquitectura/gestion-estado.md): un campo asignado en `build()` leido
  /// cuando `build()` todavia no corrio de nuevo. Los dos anteriores se
  /// arreglaron caso por caso; este quita la causa, porque sin campo cacheado
  /// no hay nada que pueda quedar viejo. Construir el DAO es envolver una
  /// referencia a la conexion: no cuesta nada.
  Future<ProductoDao> get _dao async => ProductoDao(await ref.read(databaseProvider.future));

  @override
  Future<List<Producto>> build() async {
    final db = await ref.watch(databaseProvider.future);
    return ProductoDao(db).listar();
  }

  Future<void> crear(Producto producto) async {
    final dao = await _dao;
    await dao.insertar(producto);
    state = AsyncData(await dao.listar());
  }

  Future<void> actualizar(Producto producto) async {
    final dao = await _dao;
    await dao.actualizar(producto);
    state = AsyncData(await dao.listar());
  }

  /// Soft-delete (decision 0005) — nunca borrado fisico.
  Future<void> descontinuar(String id) async {
    final dao = await _dao;
    await dao.descontinuar(id, DateTime.now());
    state = AsyncData(await dao.listar());
  }

  /// Deshace un descontinuado.
  ///
  /// Existe porque descontinuar es reversible POR DISEÑO — la 0005 lo define
  /// como una marca, no un borrado— y sin embargo no había forma de volver
  /// atrás. Un producto de temporada obligaba a crearlo de nuevo con otro id,
  /// partiendo su historial de ventas en dos.
  Future<void> recontinuar(String id) async {
    final dao = await _dao;
    await dao.recontinuar(id, DateTime.now());
    state = AsyncData(await dao.listar());
  }

  /// Borrado fisico real, solo si se cumplen las 3 condiciones de la
  /// decision 0015. El gate de sync se recibe como parametro en vez de
  /// leerse aqui adentro, para no acoplar este Notifier a SyncNotifier
  /// (decision 0019) — quien llama decide de donde sale ese booleano.
  Future<PurgarResultado> purgar(
    String id, {
    required bool todosLosDispositivosSincronizados,
  }) async {
    final dao = await _dao;
    final ventasAsociadas = await dao.contarVentasAsociadas(id);
    if (ventasAsociadas > 0) return PurgarResultado.tieneVentasAsociadas;
    if (!todosLosDispositivosSincronizados) {
      return PurgarResultado.faltaSincronizar;
    }

    await dao.purgar(id);
    state = AsyncData(await dao.listar());
    return PurgarResultado.ok;
  }
}

final productoNotifierProvider = AsyncNotifierProvider<ProductoNotifier, List<Producto>>(
  ProductoNotifier.new,
);
