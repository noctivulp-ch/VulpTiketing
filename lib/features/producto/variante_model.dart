import 'dart:convert';

/// Una forma de vender el mismo producto a otro precio: el tamaño de un café,
/// el corte del pollo, con o sin papas. Un nombre y un precio, nada más.
///
/// NO es una entidad: vive dentro de `producto.variantes` como JSON y se
/// edita en el formulario del producto (decisión 0039). Por eso no tiene DAO
/// ni Notifier propio, y por eso `updated_at` es el del producto.
class Variante {
  const Variante({required this.id, required this.nombre, required this.precio});

  /// Estable aunque se renombre. Existe por el costeo, que apunta a la
  /// variante para darle su propia receta; la venta guarda el NOMBRE, no
  /// este id, porque un libro es una foto del día (0039).
  final String id;
  final String nombre;
  final double precio;

  factory Variante.fromJson(Map<String, Object?> json) => Variante(
    id: json['id'] as String,
    nombre: json['nombre'] as String,
    precio: (json['precio'] as num).toDouble(),
  );

  Map<String, Object?> toJson() => {'id': id, 'nombre': nombre, 'precio': precio};

  Variante copyWith({String? nombre, double? precio}) =>
      Variante(id: id, nombre: nombre ?? this.nombre, precio: precio ?? this.precio);

  @override
  bool operator ==(Object other) =>
      other is Variante && other.id == id && other.nombre == nombre && other.precio == precio;

  @override
  int get hashCode => Object.hash(id, nombre, precio);

  @override
  String toString() => 'Variante($nombre: $precio)';
}

/// La lista como va en la columna. `NULL` es "sin variantes", y una lista
/// vacía también se guarda como `NULL`: no hay diferencia entre las dos y
/// guardar `[]` obligaría a todo lector a tratar dos formas del mismo nada.
String? variantesAColumna(List<Variante> variantes) =>
    variantes.isEmpty ? null : jsonEncode([for (final v in variantes) v.toJson()]);

/// Lo inverso. Tolera `NULL`, vacío y —por si un archivo viene a mano— un
/// JSON que no es lista: en los tres casos, sin variantes. Un catálogo con
/// una columna rota no puede tumbar la pantalla de venta.
List<Variante> variantesDeColumna(Object? columna) {
  if (columna is! String || columna.trim().isEmpty) return const [];
  final decodificado = jsonDecode(columna);
  if (decodificado is! List) return const [];
  return [
    for (final e in decodificado)
      if (e is Map) Variante.fromJson(Map<String, Object?>.from(e)),
  ];
}
