enum EstadoVenta { activa, revertida }

/// Cómo se cobró.
///
/// En la soda hay dos formas y **efectivo es la normal**: por eso es el valor
/// por defecto de la columna, y por eso marcar SINPE es una casilla y no un
/// selector con dos opciones — pedir que se elija en cada venta lo que nueve de
/// cada diez veces es lo mismo agrega un toque por venta a cambio de nada.
enum MetodoPago {
  efectivo('Efectivo'),
  sinpe('SINPE');

  const MetodoPago(this.etiqueta);

  final String etiqueta;

  static MetodoPago de(String? nombre) =>
      values.firstWhere((m) => m.name == nombre, orElse: () => MetodoPago.efectivo);
}

/// Ver docs/arquitectura/esquema-db.md#venta.
/// Ciclo de vida: SOLO crear o revertir (decision 0009) — nunca editar ni
/// borrar. No agregar update()/delete() a VentaNotifier sin releer 0009.
class Venta {
  const Venta({
    required this.id,
    required this.fechaHora,
    required this.estado,
    required this.updatedAt,
    this.detalle,
    this.motivoReversion,
    this.metodoPago = MetodoPago.efectivo,
    this.referenciaPago,
  });

  final String id;
  final DateTime fechaHora;
  final String? detalle;
  final EstadoVenta estado;

  /// Con qué se pagó. Efectivo salvo que se marque lo contrario al cobrar.
  final MetodoPago metodoPago;

  /// El identificador de la transferencia, cuando lo hay.
  ///
  /// Se anota **después**, y es opcional a propósito: al cobrar hay cola y
  /// nadie va a transcribir un número de doce dígitos con el cliente delante.
  /// Lo que no puede perderse es *que* fue SINPE; el número se completa con
  /// calma, o no se completa.
  final String? referenciaPago;

  /// JSON serializado (decision 0010): {tipo, detalle, revertido_por, revertido_en}.
  /// Solo no-nulo cuando estado == revertida.
  final String? motivoReversion;
  final DateTime updatedAt;

  factory Venta.fromMap(Map<String, Object?> map) {
    return Venta(
      id: map['id'] as String,
      fechaHora: DateTime.parse(map['fecha_hora'] as String),
      detalle: map['detalle'] as String?,
      estado: (map['estado'] as String) == 'revertida' ? EstadoVenta.revertida : EstadoVenta.activa,
      motivoReversion: map['motivo_reversion'] as String?,
      // Con `?` y no directo: una fila que venga de un libro todavía sin la
      // columna —otro aparato con la app vieja, un backup de antes— no puede
      // hacer reventar la lectura.
      metodoPago: MetodoPago.de(map['metodo_pago'] as String?),
      referenciaPago: map['referencia_pago'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Venta copiaCon({MetodoPago? metodoPago, String? referenciaPago, DateTime? updatedAt}) => Venta(
    id: id,
    fechaHora: fechaHora,
    estado: estado,
    detalle: detalle,
    motivoReversion: motivoReversion,
    metodoPago: metodoPago ?? this.metodoPago,
    referenciaPago: referenciaPago ?? this.referenciaPago,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'fecha_hora': fechaHora.toIso8601String(),
      'detalle': detalle,
      'estado': estado == EstadoVenta.revertida ? 'revertida' : 'activa',
      'motivo_reversion': motivoReversion,
      'metodo_pago': metodoPago.name,
      'referencia_pago': referenciaPago,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
