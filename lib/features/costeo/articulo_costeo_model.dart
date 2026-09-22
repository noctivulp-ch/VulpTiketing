/// Lo que la hoja añade a un producto o a una de sus variantes (0040).
///
/// Se identifica por `(productoId, varianteId)`, con [varianteId] vacío para
/// el producto sin variantes: una fila por cosa que se vende como una unidad.
class ArticuloCosteoRegistro {
  const ArticuloCosteoRegistro({
    required this.id,
    required this.productoId,
    required this.updatedAt,
    this.varianteId = '',
    this.unidadesPorLote = 1,
    this.otrosCostosDirectos = 0,
    this.minutosLote = 0,
    this.unidadesEstimadasMes = 0,
    this.margenObjetivo,
    this.ajustePrecio = 0,
    this.deletedAt,
  });

  final String id;
  final String productoId;
  final String varianteId;
  final int unidadesPorLote;
  final double otrosCostosDirectos;
  final double minutosLote;

  /// De reserva: el volumen que manda es el de las ventas reales cuando las
  /// hay (0040 §3).
  final int unidadesEstimadasMes;
  final double? margenObjetivo;
  final double ajustePrecio;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activo => deletedAt == null;

  /// La clave con la que el catálogo lo empareja.
  String get clave => claveDe(productoId, varianteId);
  static String claveDe(String productoId, String varianteId) => '$productoId#$varianteId';

  factory ArticuloCosteoRegistro.fromMap(Map<String, Object?> m) => ArticuloCosteoRegistro(
    id: m['id'] as String,
    productoId: m['producto_id'] as String,
    varianteId: (m['variante_id'] as String?) ?? '',
    unidadesPorLote: (m['unidades_por_lote'] as num).toInt(),
    otrosCostosDirectos: (m['otros_costos_directos'] as num).toDouble(),
    minutosLote: (m['minutos_lote'] as num).toDouble(),
    unidadesEstimadasMes: (m['unidades_estimadas_mes'] as num).toInt(),
    margenObjetivo: (m['margen_objetivo'] as num?)?.toDouble(),
    ajustePrecio: (m['ajuste_precio'] as num).toDouble(),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'producto_id': productoId,
    'variante_id': varianteId,
    'unidades_por_lote': unidadesPorLote,
    'otros_costos_directos': otrosCostosDirectos,
    'minutos_lote': minutosLote,
    'unidades_estimadas_mes': unidadesEstimadasMes,
    'margen_objetivo': margenObjetivo,
    'ajuste_precio': ajustePrecio,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  ArticuloCosteoRegistro copyWith({
    int? unidadesPorLote,
    double? otrosCostosDirectos,
    double? minutosLote,
    int? unidadesEstimadasMes,
    double? margenObjetivo,
    bool quitarMargen = false,
    double? ajustePrecio,
    DateTime? updatedAt,
  }) => ArticuloCosteoRegistro(
    id: id,
    productoId: productoId,
    varianteId: varianteId,
    unidadesPorLote: unidadesPorLote ?? this.unidadesPorLote,
    otrosCostosDirectos: otrosCostosDirectos ?? this.otrosCostosDirectos,
    minutosLote: minutosLote ?? this.minutosLote,
    unidadesEstimadasMes: unidadesEstimadasMes ?? this.unidadesEstimadasMes,
    margenObjetivo: quitarMargen ? null : (margenObjetivo ?? this.margenObjetivo),
    ajustePrecio: ajustePrecio ?? this.ajustePrecio,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt,
  );
}

/// Una línea de la receta de un artículo (0040).
class LineaRecetaRegistro {
  const LineaRecetaRegistro({
    required this.id,
    required this.articuloId,
    required this.insumoId,
    required this.cantidadPorLote,
    required this.updatedAt,
    this.notas,
    this.deletedAt,
  });

  final String id;

  /// El id de la fila de `articulo_costeo`.
  final String articuloId;
  final String insumoId;
  final double cantidadPorLote;
  final String? notas;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activa => deletedAt == null;

  factory LineaRecetaRegistro.fromMap(Map<String, Object?> m) => LineaRecetaRegistro(
    id: m['id'] as String,
    articuloId: m['articulo_id'] as String,
    insumoId: m['insumo_id'] as String,
    cantidadPorLote: (m['cantidad_por_lote'] as num).toDouble(),
    notas: m['notas'] as String?,
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'articulo_id': articuloId,
    'insumo_id': insumoId,
    'cantidad_por_lote': cantidadPorLote,
    'notas': notas,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}
