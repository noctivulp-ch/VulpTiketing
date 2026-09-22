import 'package:costeo/costeo.dart' as c;

/// Bajo qué régimen tributa el negocio (0042, y la investigación de
/// `docs/investigacion/`).
enum Regimen {
  /// El impuesto se paga como fracción de las COMPRAS del trimestre. No se
  /// cobra IVA explícito en la venta. Lo normal en una soda.
  simplificado,

  /// IVA dentro del precio de cada producto, según su tasa; se declara sobre
  /// lo vendido.
  general;

  String get etiqueta => switch (this) {
    Regimen.simplificado => 'Simplificado',
    Regimen.general => 'General',
  };
}

/// Los parámetros del negocio, una sola fila (0040). Es tabla y no
/// preferencias porque viaja por el sync: el margen objetivo es del negocio,
/// no del aparato.
///
/// [config] es lo que consume el cálculo; lo demás son los parámetros de
/// impuestos y comisiones (0042) con los que la app **construye** ese
/// `ConfigCosteo`: la comisión efectiva sale del mix real de pagos, y el
/// impuesto sobre compras solo aplica en simplificado.
class ConfigCosteoRegistro {
  const ConfigCosteoRegistro({
    required this.config,
    required this.updatedAt,
    this.regimen = Regimen.simplificado,
    this.factorIvaCompras = 0.03,
    this.factorRentaCompras = 0.025,
    this.tasaIvaPorDefecto = 0.13,
    this.comisionEfectivo = 0,
    this.comisionSinpe = 0,
  });

  static const idUnica = 'unica';

  final c.ConfigCosteo config;
  final DateTime updatedAt;
  final Regimen regimen;

  /// Simplificado: factores sobre las compras del trimestre.
  final double factorIvaCompras;
  final double factorRentaCompras;

  /// General: lo que lleva un producto que no dice otra cosa.
  final double tasaIvaPorDefecto;

  /// Por medio de pago. Efectivo no cobra; SINPE o datáfono, lo que cobre el
  /// banco. La comisión efectiva del cálculo es el promedio ponderado por el
  /// mix real de ventas.
  final double comisionEfectivo;
  final double comisionSinpe;

  /// Lo que se imputa por unidad sobre el costo de insumos en simplificado.
  double get impuestoSobreCompras => regimen == Regimen.simplificado ? factorIvaCompras + factorRentaCompras : 0;

  ConfigCosteoRegistro copyWith({
    c.ConfigCosteo? config,
    Regimen? regimen,
    double? factorIvaCompras,
    double? factorRentaCompras,
    double? tasaIvaPorDefecto,
    double? comisionEfectivo,
    double? comisionSinpe,
    DateTime? updatedAt,
  }) => ConfigCosteoRegistro(
    config: config ?? this.config,
    regimen: regimen ?? this.regimen,
    factorIvaCompras: factorIvaCompras ?? this.factorIvaCompras,
    factorRentaCompras: factorRentaCompras ?? this.factorRentaCompras,
    tasaIvaPorDefecto: tasaIvaPorDefecto ?? this.tasaIvaPorDefecto,
    comisionEfectivo: comisionEfectivo ?? this.comisionEfectivo,
    comisionSinpe: comisionSinpe ?? this.comisionSinpe,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory ConfigCosteoRegistro.fromMap(Map<String, Object?> m) => ConfigCosteoRegistro(
    config: c.ConfigCosteo(
      diasAbiertosMes: (m['dias_abiertos_mes'] as num).toInt(),
      margenObjetivo: (m['margen_objetivo'] as num).toDouble(),
      comisionMediosPago: (m['comision_medios_pago'] as num).toDouble(),
      mermaPorDefecto: (m['merma_por_defecto'] as num).toDouble(),
      tarifaManoObraHora: (m['tarifa_mano_obra_hora'] as num).toDouble(),
      redondeoPrecio: (m['redondeo_precio'] as num).toDouble(),
      metodoReparto: c.MetodoReparto.values.firstWhere(
        (r) => r.name == m['metodo_reparto'],
        orElse: () => c.MetodoReparto.unidad,
      ),
    ),
    updatedAt: DateTime.parse(m['updated_at'] as String),
    regimen: Regimen.values.firstWhere((r) => r.name == m['regimen'], orElse: () => Regimen.simplificado),
    factorIvaCompras: (m['factor_iva_compras'] as num?)?.toDouble() ?? 0.03,
    factorRentaCompras: (m['factor_renta_compras'] as num?)?.toDouble() ?? 0.025,
    tasaIvaPorDefecto: (m['tasa_iva_por_defecto'] as num?)?.toDouble() ?? 0.13,
    comisionEfectivo: (m['comision_efectivo'] as num?)?.toDouble() ?? 0,
    comisionSinpe: (m['comision_sinpe'] as num?)?.toDouble() ?? 0,
  );

  Map<String, Object?> toMap() => {
    'id': idUnica,
    'dias_abiertos_mes': config.diasAbiertosMes,
    'margen_objetivo': config.margenObjetivo,
    'comision_medios_pago': config.comisionMediosPago,
    'merma_por_defecto': config.mermaPorDefecto,
    'tarifa_mano_obra_hora': config.tarifaManoObraHora,
    'redondeo_precio': config.redondeoPrecio,
    'metodo_reparto': config.metodoReparto.name,
    'regimen': regimen.name,
    'factor_iva_compras': factorIvaCompras,
    'factor_renta_compras': factorRentaCompras,
    'tasa_iva_por_defecto': tasaIvaPorDefecto,
    'comision_efectivo': comisionEfectivo,
    'comision_sinpe': comisionSinpe,
    'updated_at': updatedAt.toIso8601String(),
  };
}
