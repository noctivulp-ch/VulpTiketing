import 'variante_model.dart';

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
    this.variantes = const [],
    this.deletedAt,
  });

  final String id;
  final String nombre;
  final String? imagen;
  final String? categoriaId;

  /// El precio del producto sin variantes, o el de referencia cuando las hay.
  /// No cambia de significado por tener variantes (0039).
  final double precioBase;

  /// Formas de venderlo a otro precio. Vacía en casi todos; ver [Variante].
  final List<Variante> variantes;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activo => deletedAt == null;
  bool get tieneVariantes => variantes.isNotEmpty;

  /// El menor de los precios que se pueden cobrar: lo que se muestra en la
  /// tarjeta cuando hay variantes ("desde ₡800").
  double get precioMinimo => tieneVariantes
      ? variantes.map((v) => v.precio).reduce((a, b) => a < b ? a : b)
      : precioBase;

  factory Producto.fromMap(Map<String, Object?> map) {
    return Producto(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      imagen: map['imagen'] as String?,
      categoriaId: map['categoria_id'] as String?,
      precioBase: (map['precio_base'] as num).toDouble(),
      variantes: variantesDeColumna(map['variantes']),
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
      'variantes': variantesAColumna(variantes),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }
}
