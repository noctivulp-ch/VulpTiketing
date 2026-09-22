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
    this.tasaIva,
    this.deletedAt,
  });

  final String id;
  final String nombre;
  final String? imagen;
  final String? categoriaId;

  /// El precio del producto sin variantes; con variantes, el de la que está
  /// **por defecto** — el formulario los guarda en sincronía. Así todo lo que
  /// lee `precio_base` sigue valiendo (0039).
  final double precioBase;

  /// Formas de venderlo a otro precio. Vacía en casi todos; ver [Variante].
  final List<Variante> variantes;

  /// IVA de este producto en régimen general (0,13, 0,04, 0,02, 0,01, 0).
  /// Nula = la tasa por defecto de Ajustes del costeo (decisión 0042). En
  /// régimen simplificado no se usa: ahí el impuesto va sobre las compras.
  final double? tasaIva;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activo => deletedAt == null;
  bool get tieneVariantes => variantes.isNotEmpty;

  /// La variante que se vende si no se elige otra: la marcada, o la primera.
  /// Nula sin variantes.
  Variante? get variantePorDefecto =>
      tieneVariantes ? variantes.firstWhere((v) => v.porDefecto, orElse: () => variantes.first) : null;

  /// El menor de los precios que se pueden cobrar.
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
      tasaIva: (map['tasa_iva'] as num?)?.toDouble(),
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
      'tasa_iva': tasaIva,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }
}
