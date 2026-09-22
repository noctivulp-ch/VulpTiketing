/// Una compra de un insumo: cuántas presentaciones, cuánto trae cada una y
/// cuánto se pagó por todo (decisión 0041). Vive en el libro, con las ventas.
class CompraInsumo {
  const CompraInsumo({
    required this.id,
    required this.insumoId,
    required this.fecha,
    required this.presentaciones,
    required this.contenido,
    required this.pagado,
    required this.updatedAt,
    this.notas,
    this.deletedAt,
  });

  final String id;
  final String insumoId;
  final DateTime fecha;

  /// Cuántos bultos, cajas, botellas. Admite fracción (medio saco).
  final double presentaciones;

  /// Cuánto trae CADA presentación, en la unidad base del insumo.
  final double contenido;

  /// Lo pagado por todas las presentaciones juntas.
  final double pagado;
  final String? notas;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activa => deletedAt == null;

  /// Unidades base que entraron con esta compra.
  double get unidades => presentaciones * contenido;

  /// Lo que costó cada unidad base en esta compra.
  double get costoUnitario => unidades <= 0 ? 0 : pagado / unidades;

  factory CompraInsumo.fromMap(Map<String, Object?> m) => CompraInsumo(
    id: m['id'] as String,
    insumoId: m['insumo_id'] as String,
    fecha: DateTime.parse(m['fecha'] as String),
    presentaciones: (m['presentaciones'] as num).toDouble(),
    contenido: (m['contenido'] as num).toDouble(),
    pagado: (m['pagado'] as num).toDouble(),
    notas: m['notas'] as String?,
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'insumo_id': insumoId,
    'fecha': fecha.toIso8601String(),
    'presentaciones': presentaciones,
    'contenido': contenido,
    'pagado': pagado,
    'notas': notas,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}
