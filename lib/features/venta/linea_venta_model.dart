/// Ver docs/arquitectura/esquema-db.md#lineaventa y decision 0016 (linea
/// libre). Exactamente uno de productoId/nombreLibre debe estar presente
/// (mismo CHECK que en SQLite) — validar en el constructor evita filas
/// invalidas antes de llegar a la base.
class LineaVenta {
  LineaVenta({
    required this.id,
    required this.ventaId,
    required this.precioAplicado,
    required this.updatedAt,
    this.productoId,
    this.nombreLibre,
    this.cantidad = 1,
    this.nota,
    this.variante,
  }) : assert(
         (productoId != null) != (nombreLibre != null),
         'Exactamente uno de productoId o nombreLibre debe estar presente (decision 0016)',
       );

  final String id;
  final String ventaId;
  final String? productoId;

  /// Solo si productoId es null (decision 0016).
  final String? nombreLibre;

  /// Foto del precio al momento de vender — nunca un lookup en vivo a
  /// producto.precioBase (ver docs/arquitectura/esquema-db.md).
  final double precioAplicado;
  final int cantidad;

  /// Descriptivo opcional, tipicamente para justificar precioAplicado
  /// distinto al base (decision 0013).
  final String? nota;

  /// El NOMBRE de la variante vendida, si el producto tenía. Foto del día,
  /// como [precioAplicado]: si la variante se renombra después, esta línea
  /// sigue diciendo lo que se vendió (decisión 0039). Null en una línea libre
  /// y en la de un producto sin variantes.
  final String? variante;
  final DateTime updatedAt;

  /// Qué se vendió, para leerlo: el nombre del producto y, si hubo, la
  /// variante detrás de un punto medio. Es el mismo texto que arma el SQL de
  /// Reportes, para que una venta se lea igual en el carrito que en el reporte.
  String describir(String nombreProducto) =>
      variante == null ? nombreProducto : '$nombreProducto · $variante';

  factory LineaVenta.fromMap(Map<String, Object?> map) {
    return LineaVenta(
      id: map['id'] as String,
      ventaId: map['venta_id'] as String,
      productoId: map['producto_id'] as String?,
      nombreLibre: map['nombre_libre'] as String?,
      precioAplicado: (map['precio_aplicado'] as num).toDouble(),
      cantidad: map['cantidad'] as int,
      nota: map['nota'] as String?,
      variante: map['variante'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'venta_id': ventaId,
      'producto_id': productoId,
      'nombre_libre': nombreLibre,
      'precio_aplicado': precioAplicado,
      'cantidad': cantidad,
      'nota': nota,
      'variante': variante,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
