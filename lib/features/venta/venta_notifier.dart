import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import 'venta_dao.dart';
import 'venta_model.dart';

/// Venta ya persistida (decision 0019) — solo lectura y revertir. Nunca
/// agregar update()/delete() aqui, ver decision 0009: una Venta no se edita
/// ni se borra.
class VentaNotifier extends AsyncNotifier<List<Venta>> {
  /// Ver el comentario equivalente en ProductoNotifier: el DAO se resuelve en
  /// cada llamada, nunca se guarda en un campo.
  Future<VentaDao> get _dao async => VentaDao(await ref.read(databaseProvider.future));

  @override
  Future<List<Venta>> build() async {
    final db = await ref.watch(databaseProvider.future);
    return VentaDao(db).listar();
  }

  /// Exige motivo estructurado (decision 0010): tipo, detalle, quien, cuando.
  Future<void> revertir({
    required String ventaId,
    required String tipo,
    required String detalle,
    required String revertidoPor,
  }) async {
    final motivo = jsonEncode({
      'tipo': tipo,
      'detalle': detalle,
      'revertido_por': revertidoPor,
      'revertido_en': DateTime.now().toIso8601String(),
    });
    final dao = await _dao;
    await dao.revertir(ventaId, motivo, DateTime.now());
    state = AsyncData(await dao.listar());
  }
}

final ventaNotifierProvider = AsyncNotifierProvider<VentaNotifier, List<Venta>>(VentaNotifier.new);
