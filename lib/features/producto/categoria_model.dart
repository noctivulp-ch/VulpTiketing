/// Ver docs/arquitectura/esquema-db.md#categoria y decision 0018
/// (agrupa Producto para navegacion/busqueda, sin peso en reportes).
class Categoria {
  const Categoria({
    required this.id,
    required this.nombre,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String nombre;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activa => deletedAt == null;

  factory Categoria.fromMap(Map<String, Object?> map) {
    return Categoria(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.parse(map['deleted_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }
}
