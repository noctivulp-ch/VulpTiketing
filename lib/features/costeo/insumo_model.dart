import 'package:costeo/costeo.dart' as c;

/// Una materia prima del costeo (decisión 0040). Ver `esquema-db.md#insumo`.
/// Ciclo de vida: crear, actualizar, descontinuar. Sin purgar: una receta
/// puede seguir nombrándolo y se ve como alerta.
class InsumoRegistro {
  const InsumoRegistro({
    required this.id,
    required this.nombre,
    required this.unidadBase,
    required this.contenidoPorCompra,
    required this.precioCompra,
    required this.updatedAt,
    this.merma,
    this.proveedor,
    this.notas,
    this.deletedAt,
  });

  final String id;
  final String nombre;
  final c.UnidadBase unidadBase;
  final double contenidoPorCompra;
  final double precioCompra;
  final double? merma;
  final String? proveedor;
  final String? notas;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activo => deletedAt == null;

  /// La entidad pura que consume el cálculo.
  c.Insumo get puro => c.Insumo(
    id: id,
    nombre: nombre,
    unidadBase: unidadBase,
    contenidoPorCompra: contenidoPorCompra,
    precioCompra: precioCompra,
    merma: merma,
  );

  factory InsumoRegistro.fromMap(Map<String, Object?> m) => InsumoRegistro(
    id: m['id'] as String,
    nombre: m['nombre'] as String,
    unidadBase: c.UnidadBase.values.firstWhere(
      (u) => u.name == m['unidad_base'],
      orElse: () => c.UnidadBase.gramo,
    ),
    contenidoPorCompra: (m['contenido_por_compra'] as num).toDouble(),
    precioCompra: (m['precio_compra'] as num).toDouble(),
    merma: (m['merma'] as num?)?.toDouble(),
    proveedor: m['proveedor'] as String?,
    notas: m['notas'] as String?,
    updatedAt: DateTime.parse(m['updated_at'] as String),
    deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'nombre': nombre,
    'unidad_base': unidadBase.name,
    'contenido_por_compra': contenidoPorCompra,
    'precio_compra': precioCompra,
    'merma': merma,
    'proveedor': proveedor,
    'notas': notas,
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

/// Etiquetas de la unidad base para las pantallas.
extension UnidadBaseTexto on c.UnidadBase {
  String get abreviatura => switch (this) {
    c.UnidadBase.gramo => 'g',
    c.UnidadBase.mililitro => 'ml',
    c.UnidadBase.unidad => 'u',
  };
  String get nombre => switch (this) {
    c.UnidadBase.gramo => 'gramo',
    c.UnidadBase.mililitro => 'mililitro',
    c.UnidadBase.unidad => 'unidad',
  };
}
