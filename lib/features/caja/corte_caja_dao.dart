import 'package:sqflite/sqflite.dart';

import 'corte_caja_model.dart';

/// Acceso a datos de los cortes de caja — mismo patrón que CategoriaDao.
class CorteCajaDao {
  CorteCajaDao(this._db);

  final Database _db;

  /// Los cortes de un día, del más viejo al más nuevo.
  Future<List<CorteCaja>> listarDelDia(String dia) async {
    final rows = await _db.query(
      'corte_caja',
      where: 'dia = ? AND deleted_at IS NULL',
      whereArgs: [dia],
      orderBy: 'fecha_hora',
    );
    return rows.map(CorteCaja.fromMap).toList();
  }

  Future<void> insertar(CorteCaja corte) {
    return _db.insert('corte_caja', corte.toMap());
  }

  /// Cambia el monto de un corte ya anotado, conservando su id y su hora.
  ///
  /// El id se conserva para que la sincronización lo vea como la misma fila
  /// corregida y no como un corte nuevo: si cambiara, el otro teléfono acabaría
  /// con dos cortes del mismo momento.
  ///
  /// Y la hora también, porque es la frontera del tramo: el conteo se hizo a esa
  /// hora aunque el dedazo se arregle dos minutos después, así que mover la
  /// frontera sacaría del tramo ventas que sí ocurrieron dentro.
  Future<void> corregirMonto(String id, double monto, DateTime cuando) {
    return _db.update(
      'corte_caja',
      {'monto': monto, 'updated_at': cuando.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cuánto efectivo entró entre [desde] y [hasta].
  ///
  /// Solo efectivo: el SINPE no cae en la caja, así que sumarlo daría un
  /// esperado que nunca va a coincidir con lo que hay dentro.
  ///
  /// Y solo desde el último corte, no desde que abrió el día: en el cambio de
  /// turno se guarda la mayor parte del efectivo, así que contar la mañana otra
  /// vez dejaría el esperado por encima de lo que hay para siempre.
  ///
  /// Se agrega en SQL igual que el resto de los reportes: traer las ventas para
  /// sumarlas en Dart es justo lo que se corrigió cuando el reporte del año no
  /// terminaba.
  Future<double> efectivoEntre(DateTime desde, DateTime hasta) async {
    final rows = await _db.rawQuery(
      '''
      SELECT SUM(lv.precio_aplicado * lv.cantidad) AS total
      FROM linea_venta lv
      JOIN venta v ON v.id = lv.venta_id
      WHERE v.estado = 'activa'
        AND v.metodo_pago = 'efectivo'
        AND v.fecha_hora >= ? AND v.fecha_hora < ?
    ''',
      [desde.toIso8601String(), hasta.toIso8601String()],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }
}
