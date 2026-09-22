import 'package:costeo/costeo.dart' as c;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/db_providers.dart';
import 'articulo_costeo_model.dart';
import 'config_costeo_model.dart';
import 'costeo_dao.dart';
import 'costo_fijo_model.dart';
import 'insumo_model.dart';

const _uuid = Uuid();

/// Los Notifiers del costeo (0040), uno por entidad y con solo las operaciones
/// de su ciclo de vida (0009). Comparten archivo porque son cortos y nacen
/// juntos; no comparten ninguna clase base.
///
/// Todos construyen el DAO en cada llamada: un campo asignado en `build()`
/// sobrevive a que la conexión se reemplace (ver gestion-estado.md).

class InsumoNotifier extends AsyncNotifier<List<InsumoRegistro>> {
  Future<CosteoDao> get _dao async => CosteoDao(await ref.read(databaseProvider.future));

  @override
  Future<List<InsumoRegistro>> build() async => CosteoDao(await ref.watch(databaseProvider.future)).listarInsumos();

  Future<void> crear(InsumoRegistro i) async {
    final dao = await _dao;
    await dao.insertarInsumo(i);
    state = AsyncData(await dao.listarInsumos());
  }

  Future<void> actualizar(InsumoRegistro i) async {
    final dao = await _dao;
    await dao.actualizarInsumo(i);
    state = AsyncData(await dao.listarInsumos());
  }

  /// Marca, no borra: una receta puede seguir nombrándolo.
  Future<void> descontinuar(String id) async {
    final dao = await _dao;
    await dao.descontinuarInsumo(id, DateTime.now());
    state = AsyncData(await dao.listarInsumos());
  }
}

final insumoNotifierProvider = AsyncNotifierProvider<InsumoNotifier, List<InsumoRegistro>>(InsumoNotifier.new);

class CostoFijoNotifier extends AsyncNotifier<List<CostoFijoRegistro>> {
  Future<CosteoDao> get _dao async => CosteoDao(await ref.read(databaseProvider.future));

  @override
  Future<List<CostoFijoRegistro>> build() async =>
      CosteoDao(await ref.watch(databaseProvider.future)).listarCostosFijos();

  Future<void> crear(CostoFijoRegistro c) async {
    final dao = await _dao;
    await dao.insertarCostoFijo(c);
    state = AsyncData(await dao.listarCostosFijos());
  }

  Future<void> actualizar(CostoFijoRegistro c) async {
    final dao = await _dao;
    await dao.actualizarCostoFijo(c);
    state = AsyncData(await dao.listarCostosFijos());
  }

  Future<void> descontinuar(String id) async {
    final dao = await _dao;
    await dao.descontinuarCostoFijo(id, DateTime.now());
    state = AsyncData(await dao.listarCostosFijos());
  }
}

final costoFijoNotifierProvider =
    AsyncNotifierProvider<CostoFijoNotifier, List<CostoFijoRegistro>>(CostoFijoNotifier.new);

/// La única fila de parámetros, con régimen y comisiones (0042). Sin fila
/// guardada vale la de fábrica.
class ConfigCosteoNotifier extends AsyncNotifier<ConfigCosteoRegistro> {
  Future<CosteoDao> get _dao async => CosteoDao(await ref.read(databaseProvider.future));

  @override
  Future<ConfigCosteoRegistro> build() async {
    final guardada = await CosteoDao(await ref.watch(databaseProvider.future)).leerConfig();
    return guardada ?? ConfigCosteoRegistro(config: const c.ConfigCosteo(), updatedAt: DateTime(2000));
  }

  Future<void> guardar(ConfigCosteoRegistro registro) async {
    final dao = await _dao;
    final ahora = registro.copyWith(updatedAt: DateTime.now());
    await dao.guardarConfig(ahora);
    state = AsyncData(ahora);
  }
}

final configCosteoProvider =
    AsyncNotifierProvider<ConfigCosteoNotifier, ConfigCosteoRegistro>(ConfigCosteoNotifier.new);

/// Los datos de costeo de cada artículo (producto o variante), y sus recetas.
///
/// Van juntos porque una receta no existe sin su artículo y se editan en la
/// misma pantalla; la receta no tiene ciclo de vida propio más allá de poner
/// y quitar líneas.
class ArticuloCosteoNotifier extends AsyncNotifier<EstadoArticulos> {
  Future<CosteoDao> get _dao async => CosteoDao(await ref.read(databaseProvider.future));

  @override
  Future<EstadoArticulos> build() async => _leer(CosteoDao(await ref.watch(databaseProvider.future)));

  Future<EstadoArticulos> _leer(CosteoDao dao) async =>
      EstadoArticulos(articulos: await dao.listarArticulos(), lineas: await dao.listarLineas());

  /// El artículo de un producto/variante, creándolo con valores de fábrica
  /// si todavía no tiene: la pantalla no distingue "nunca costeado" de
  /// "costeado con ceros" porque el resultado es el mismo.
  Future<ArticuloCosteoRegistro> asegurar(String productoId, String varianteId) async {
    final dao = await _dao;
    final estado = await _leer(dao);
    final existente = estado.articuloDe(productoId, varianteId);
    if (existente != null) return existente;
    final nuevo = ArticuloCosteoRegistro(
      id: _uuid.v4(),
      productoId: productoId,
      varianteId: varianteId,
      updatedAt: DateTime.now(),
    );
    await dao.guardarArticulo(nuevo);
    state = AsyncData(await _leer(dao));
    return nuevo;
  }

  Future<void> guardarArticulo(ArticuloCosteoRegistro a) async {
    final dao = await _dao;
    await dao.guardarArticulo(a);
    state = AsyncData(await _leer(dao));
  }

  /// Pone o reemplaza la cantidad de un insumo en la receta del artículo.
  Future<void> ponerLinea(String articuloId, String insumoId, double cantidadPorLote, {String? notas}) async {
    final dao = await _dao;
    final estado = await _leer(dao);
    final previa = estado.lineas.where((l) => l.articuloId == articuloId && l.insumoId == insumoId).firstOrNull;
    await dao.guardarLinea(
      LineaRecetaRegistro(
        id: previa?.id ?? _uuid.v4(),
        articuloId: articuloId,
        insumoId: insumoId,
        cantidadPorLote: cantidadPorLote,
        notas: notas ?? previa?.notas,
        updatedAt: DateTime.now(),
      ),
    );
    state = AsyncData(await _leer(dao));
  }

  Future<void> quitarLinea(String lineaId) async {
    final dao = await _dao;
    await dao.descontinuarLinea(lineaId, DateTime.now());
    state = AsyncData(await _leer(dao));
  }
}

class EstadoArticulos {
  const EstadoArticulos({required this.articulos, required this.lineas});
  final List<ArticuloCosteoRegistro> articulos;
  final List<LineaRecetaRegistro> lineas;

  ArticuloCosteoRegistro? articuloDe(String productoId, String varianteId) =>
      articulos.where((a) => a.activo && a.productoId == productoId && a.varianteId == varianteId).firstOrNull;

  List<LineaRecetaRegistro> lineasDe(String articuloId) =>
      [for (final l in lineas) if (l.activa && l.articuloId == articuloId) l];
}

final articuloCosteoProvider =
    AsyncNotifierProvider<ArticuloCosteoNotifier, EstadoArticulos>(ArticuloCosteoNotifier.new);
