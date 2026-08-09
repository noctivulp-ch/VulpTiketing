/// Ver docs/arquitectura/esquema-db.md#categoria y decision 0018
/// (agrupa Producto para navegacion/busqueda, sin peso en reportes).
class Categoria {
  const Categoria({
    required this.id,
    required this.nombre,
    required this.updatedAt,
    this.icono,
    this.deletedAt,
  });

  final String id;
  final String nombre;

  /// La clave del icono elegido a mano, o `null` para que salga del nombre.
  ///
  /// El acierto automatico por nombre funciona para casi todas —"Arroces" da
  /// tazon, "Batidos en Leche" da licuadora— pero no es infalible, y una
  /// categoria con la cara equivocada es peor que una sin cara: dice algo que
  /// no es. Esto es la salida manual, y por eso `null` es el estado normal.
  final String? icono;

  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get activa => deletedAt == null;

  /// Una copia con lo que se le cambie, conservando el resto.
  ///
  /// Existe por un fallo concreto: renombrar una categoria se hacia
  /// construyendo una `Categoria` nueva a mano, y como el constructor no pide
  /// `icono`, la elección manual se perdía en silencio. Cada campo nuevo que se
  /// agregue tendría el mismo problema en cada sitio que reconstruya a mano.
  ///
  /// `icono` se pasa envuelto para poder distinguir "no lo toques" de "ponelo
  /// en automático": con un `String?` suelto las dos cosas serían `null`.
  Categoria copyWith({
    String? nombre,
    ({String? valor})? icono,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Categoria(
      id: id,
      nombre: nombre ?? this.nombre,
      icono: icono == null ? this.icono : icono.valor,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  factory Categoria.fromMap(Map<String, Object?> map) {
    return Categoria(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      icono: map['icono'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
      deletedAt: map['deleted_at'] == null ? null : DateTime.parse(map['deleted_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'icono': icono,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }
}
