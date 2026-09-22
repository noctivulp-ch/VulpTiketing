import 'package:costeo/costeo.dart' as c;

/// Los parámetros del negocio, una sola fila (0040). Es tabla y no
/// preferencias porque viaja por el sync: el margen objetivo es del negocio,
/// no del aparato.
class ConfigCosteoRegistro {
  const ConfigCosteoRegistro({
    required this.config,
    required this.updatedAt,
  });

  static const idUnica = 'unica';

  final c.ConfigCosteo config;
  final DateTime updatedAt;

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
    'updated_at': updatedAt.toIso8601String(),
  };
}
