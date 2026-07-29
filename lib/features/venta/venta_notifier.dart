import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db_providers.dart';
import 'venta_dao.dart';
import 'venta_model.dart';

/// Venta ya persistida (decision 0019) — solo lectura y revertir. Nunca
/// agregar update()/delete() aqui, ver decision 0009: una Venta no se edita
/// ni se borra.
class VentaNotifier extends AsyncNotifier<List<Venta>> {
  // `late` sin `final` — ver comentario equivalente en ProductoNotifier:
  // Riverpod reutiliza esta instancia y vuelve a llamar build() al
  // invalidar el provider, `final` rompia con LateInitializationError.
  late VentaDao _dao;

  @override
  Future<List<Venta>> build() async {
    final db = await ref.watch(databaseProvider.future);
    _dao = VentaDao(db);
    return _dao.listar();
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
    await _dao.revertir(ventaId, motivo, DateTime.now());
    state = AsyncData(await _dao.listar());
  }
}

final ventaNotifierProvider =
    AsyncNotifierProvider<VentaNotifier, List<Venta>>(VentaNotifier.new);
