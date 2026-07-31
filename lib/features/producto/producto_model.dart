/// Ver docs/arquitectura/esquema-db.md#producto.
/// Ciclo de vida completo (crear/leer/actualizar/descontinuar/purgar) en
/// docs/arquitectura/gestion-estado.md — no agregar operaciones aqui sin
/// actualizar esa tabla primero (regla dura de CLAUDE.md).
class Producto {
  const Producto({
    required this.id,
    required this.nombre,
    required this.precioBase,
    required this.updatedAt,
    this.imagen,
    this.categoriaId,
    this.deletedAt,
  });

  final String id;
  final String nombre;
  final String? imagen;
  final String? categoriaId;
  final double precioBase;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activo => deletedAt == null;

  factory Producto.fromMap(Map<String, Object?> map) {
    return Producto(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      imagen: map['imagen'] as String?,
      categoriaId: map['categoria_id'] as String?,
      precioBase: (map['precio_base'] as num).toDouble(),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] == null ? null : DateTime.parse(map['deleted_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'imagen': imagen,
      'categoria_id': categoriaId,
      'precio_base': precioBase,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }
}
