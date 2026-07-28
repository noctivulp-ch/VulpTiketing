enum EstadoVenta { activa, revertida }

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
  });

  final String id;
  final DateTime fechaHora;
  final String? detalle;
  final EstadoVenta estado;

  /// JSON serializado (decision 0010): {tipo, detalle, revertido_por, revertido_en}.
  /// Solo no-nulo cuando estado == revertida.
  final String? motivoReversion;
  final DateTime updatedAt;

  factory Venta.fromMap(Map<String, Object?> map) {
    return Venta(
      id: map['id'] as String,
      fechaHora: DateTime.parse(map['fecha_hora'] as String),
      detalle: map['detalle'] as String?,
      estado: (map['estado'] as String) == 'revertida'
          ? EstadoVenta.revertida
          : EstadoVenta.activa,
      motivoReversion: map['motivo_reversion'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'fecha_hora': fechaHora.toIso8601String(),
      'detalle': detalle,
      'estado': estado == EstadoVenta.revertida ? 'revertida' : 'activa',
      'motivo_reversion': motivoReversion,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
