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

  /// Anota el identificador de la transferencia de una venta SINPE.
  ///
  /// **Sí, esto escribe sobre una venta guardada**, y la decisión 0009 dice que
  /// Venta solo se crea o se revierte. La excepción es deliberada y acotada:
  /// la referencia no es un dato de la venta sino del cobro —no cambia importes,
  /// líneas ni estado— y el flujo real la exige, porque al cobrar hay cola y
  /// nadie transcribe doce dígitos con el cliente delante.
  ///
  /// Lo que 0009 protege es que una venta no se pueda "arreglar" después. Eso
  /// sigue igual: no hay `actualizar()` ni `eliminar()`, y esta operación no
  /// puede convertirse en uno — escribe una sola columna y nada más.
  ///
  /// Pasar `null` o vacío la borra: alguien anota mal un número y tiene que
  /// poder dejarlo como estaba.
  Future<void> anotarReferenciaDePago(String ventaId, String? referencia) async {
    final dao = await _dao;
    await dao.anotarReferenciaDePago(ventaId, referencia, DateTime.now());
    state = AsyncData(await dao.listar());
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
