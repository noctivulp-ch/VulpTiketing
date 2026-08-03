import 'package:sqflite/sqflite.dart';

import 'linea_venta_model.dart';
import 'venta_model.dart';

class VentaDao {
  VentaDao(this._db);

  final Database _db;

  Future<List<Venta>> listar() async {
    final rows = await _db.query('venta', orderBy: 'fecha_hora DESC');
    return rows.map(Venta.fromMap).toList();
  }

  Future<List<LineaVenta>> lineasDe(String ventaId) async {
    final rows = await _db.query('linea_venta', where: 'venta_id = ?', whereArgs: [ventaId]);
    return rows.map(LineaVenta.fromMap).toList();
  }

  /// Crea la Venta y sus lineas en una sola transaccion — o se guardan
  /// todas o ninguna.
  Future<void> guardar(Venta venta, List<LineaVenta> lineas) async {
    await _db.transaction((txn) async {
      await txn.insert('venta', venta.toMap());
      for (final linea in lineas) {
        await txn.insert('linea_venta', linea.toMap());
      }
    });
  }

  /// Unica transicion permitida sobre una Venta ya guardada (decision 0009).
  /// Anota el identificador de la transferencia de una venta ya cobrada.
  ///
  /// Es la ÚNICA columna de `venta` que se puede escribir después de guardarla,
  /// aparte de la reversión. No toca importes, líneas ni estado: es una
  /// anotación sobre cómo entró la plata, no una corrección de la venta. Ver la
  /// decisión 0032 y el porqué en `VentaNotifier.anotarReferenciaDePago`.
  ///
  /// Vacío se guarda como `NULL`: "sin referencia" es la ausencia del dato, no
  /// una cadena vacía que después haya que distinguir en cada consulta.
  Future<void> anotarReferenciaDePago(String id, String? referencia, DateTime cuando) {
    final limpia = referencia?.trim();
    return _db.update(
      'venta',
      {
        'referencia_pago': limpia == null || limpia.isEmpty ? null : limpia,
        'updated_at': cuando.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> revertir(String id, String motivoReversionJson, DateTime cuando) {
    return _db.update(
      'venta',
      {
        'estado': 'revertida',
        'motivo_reversion': motivoReversionJson,
        'updated_at': cuando.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
