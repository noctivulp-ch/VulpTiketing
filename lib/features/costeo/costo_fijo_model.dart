import 'package:costeo/costeo.dart' as c;

/// Un gasto del mes que existe aunque no se venda nada (0040).
class CostoFijoRegistro {
  const CostoFijoRegistro({
    required this.id,
    required this.concepto,
    required this.montoMensual,
    required this.updatedAt,
    this.notas,
    this.deletedAt,
  });

  final String id;
  final String concepto;
  final double montoMensual;
  final String? notas;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activo => deletedAt == null;
  c.CostoFijo get puro => c.CostoFijo(id: id, concepto: concepto, montoMensual: montoMensual);

  factory CostoFijoRegistro.fromMap(Map<String, Object?> m) => CostoFijoRegistro(
    id: m['id'] as String,
    concepto: m['concepto'] as String,
    montoMensual: (m['monto_mensual'] as num).toDouble(),
    notas: m['notas'] as String?,
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'concepto': concepto,
    'monto_mensual': montoMensual,
    'notas': notas,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}
